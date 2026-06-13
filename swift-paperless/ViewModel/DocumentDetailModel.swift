//
//  DocumentDetailModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import AppShared
import DataModel
import Foundation
import Networking
import PDFKit
import SwiftUI
import os

enum DocumentDownloadState: Equatable {
  case initial
  case loading
  case loaded(url: URL, document: PDFDocument)
  case error

  static func == (lhs: DocumentDownloadState, rhs: DocumentDownloadState) -> Bool {
    switch (lhs, rhs) {
    case (.initial, .initial), (.loading, .loading), (.loaded, .loaded), (.error, .error):
      true
    default:
      false
    }
  }
}

@MainActor
@Observable
class DocumentDetailModel {
  var download: DocumentDownloadState = .initial
  var downloadProgress: Double = 0.0

  enum OriginalDownloadState {
    case initial
    case loading
    case loaded(url: URL)
    case error
  }

  var originalDownload: OriginalDownloadState = .initial

  @ObservationIgnored
  var store: DocumentStore
  @ObservationIgnored
  var connection: Connection?

  var document: Document

  // Not fully used by the edit model yet (I think we're loading suggestions twice right now)
  var suggestions = Suggestions()

  var metadata: Metadata?

  init(
    store: DocumentStore, connection: Connection?, document: Document
  ) {
    self.store = store
    self.connection = connection
    self.document = document
  }

  /// Load everything a freshly-opened (or pulled-to-refresh) document needs from
  /// the server, best-effort.
  ///
  /// `loadDocument()` runs first and alone: it resolves the full-perms document
  /// (and so caches it, which the file-metadata version key depends on) before
  /// the PDF download validates the on-disk cache against the server's
  /// `modified`. The three enrichments — file-metadata, notes, edit suggestions —
  /// only need the document id, so they run concurrently afterwards.
  ///
  /// Each step always logs its failure. Whether it's *surfaced* is the caller's
  /// choice via `onError`: an on-appear load (`.task`) passes nothing and stays
  /// silent (the load isn't user-initiated, and the one critical failure — the
  /// PDF — already shows via `download == .error`); a pull-to-refresh passes a
  /// handler so failures toast. Offline-connectivity errors are dropped by
  /// `ErrorController.shouldSuppress`, so a parallel offline refresh won't spam.
  func load(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    await loadDocument(onError: onError)
    async let metadata: Void = loadMetadata(onError: onError)
    async let notes: Void = loadNotes(onError: onError)
    async let suggestions: Void = loadSuggestionsQuietly(onError: onError)
    _ = await (metadata, notes, suggestions)
  }

  func loadMetadata(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    do {
      metadata = try await store.repository.metadata(documentId: document.id)
    } catch is CancellationError {
    } catch {
      Logger.shared.error("Error loading document metadata: \(error)")
      onError?(error)
    }
  }

  /// Warm the notes cache on open so they're available offline later. The notes
  /// view fetches its own (network-first) copy when presented; this just ensures
  /// a document opened online has its notes written through to the cache even if
  /// the user never taps the notes button. Routed through `store.notes(for:)` so
  /// the `.note` view-permission gate is respected.
  func loadNotes(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    do {
      _ = try await store.notes(for: document)
    } catch is CancellationError {
    } catch {
      Logger.shared.error("Error loading document notes: \(error)")
      onError?(error)
    }
  }

  /// The quiet (open-path) form of `loadSuggestions()`: suggestions are an
  /// edit-sheet enrichment. `updateDocument()` calls the throwing
  /// `loadSuggestions()` directly, where the error propagates into the edit-save
  /// flow; here a failure is logged and only surfaced when `onError` is supplied.
  private func loadSuggestionsQuietly(onError: (@MainActor @Sendable (any Error) -> Void)?) async {
    do {
      try await loadSuggestions()
    } catch is CancellationError {
    } catch {
      Logger.shared.error("Error loading document suggestions: \(error)")
      onError?(error)
    }
  }

  func loadDocument(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    // Resolve the fresh document FIRST so the download path can validate
    // the ContentStore cache against the server's current `modified`
    // timestamp. If we kicked off both in parallel, a stale `modified`
    // could validate an out-of-date cached PDF before the metadata refresh
    // landed — surfacing old content alongside fresh metadata.
    do {
      if let updated = try await store.document(id: document.id) {
        document = updated
      }
    } catch is CancellationError {
    } catch {
      Logger.shared.error("Error updating document with full perms for editing: \(error)")
      onError?(error)
    }

    switch download {
    case .initial:
      let setLoading = Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        download = .loading
      }
      // Cancel the delayed `.loading` flip on *every* exit path. Without this
      // the error path leaves `setLoading` pending, and 0.5s later it overwrites
      // the just-set `.error` back to `.loading` — pinning the preview's loading
      // overlay on screen even though the download already failed.
      defer { setLoading.cancel() }
      do {
        let url = try await store.repository.download(
          document: document,
          original: false,
          progress: { @Sendable value in
            Task { @MainActor in
              self.downloadProgress = value
            }
          })

        guard let pdfDocument = await PDFDocument.loadBackground(url: url) else {
          download = .error
          break
        }

        download = .loaded(url: url, document: pdfDocument)

        // Start downloading the original in the background
        Task { await downloadOriginal() }
      } catch is CancellationError {
      } catch {
        download = .error
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
      }

    default:
      break
    }
  }

  func downloadOriginal() async {
    guard case .initial = originalDownload else { return }
    originalDownload = .loading
    do {
      let url = try await store.repository.download(document: document, original: true)
      originalDownload = .loaded(url: url)
    } catch {
      originalDownload = .error
      Logger.shared.error("Error downloading original document: \(error)")
    }
  }

  func loadSuggestions() async throws {
    suggestions = try await store.repository.suggestions(documentId: document.id)
  }

  func updateDocument() async throws {
    let updated = try await store.updateDocument(document)
    self.document = updated
    try await loadSuggestions()
  }

  var userCanChange: Bool {
    store.userCanChange(document: document)
  }

  var userCanView: Bool {
    store.userCanView(document: document)
  }

  var documentUrl: URL? {
    guard let connection else { return nil }
    return Endpoint.documentUrl(documentId: document.id).url(url: connection.url)
  }

  // @TODO: Extract `private var serverURL: URL?` from `(store.repository as? ApiRepository)?.connection.url`,
  // use it in both `documentUrl` and `deepLinks`, then drop the `connection` property and propagation through init/protocol/view.
  var deepLinks: (withServer: Route?, withoutServer: Route?) {
    let withServer: Route? = (store.repository as? ApiRepository).flatMap {
      let serverURL = $0.connection.url
      guard let server = serverURL.stringDroppingScheme else { return nil }
      return Route(action: .document(id: document.id, edit: nil), server: server)
    }

    let withoutServer: Route? = Route(action: .document(id: document.id, edit: nil))
    return (withServer, withoutServer)

  }
}
