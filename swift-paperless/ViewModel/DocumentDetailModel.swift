//
//  DocumentDetailModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import AppShared
import Common
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

  // `.loaded` compares its payload, not just its case. SwiftUI uses the `==` of
  // a view's Equatable stored properties when it diffs, and
  // `IntegratedDocumentPreview` takes this value as a stored property — so
  // treating every `.loaded` as equal made swapping one document for another (a
  // re-download after a server-side version bump) invisible: the preview
  // subtree was never re-evaluated, and the new `PDFDocument` never reached
  // `PDFKitView`.
  //
  // It also silently disabled `.task(id: downloadState)` and
  // `.animation(value: downloadState)` across a `.loaded` → `.loaded` change.
  //
  // `PDFDocument` is a non-Equatable class, which is presumably why this was
  // hand-rolled; identity is the right comparison for it, since
  // `loadBackground` constructs a fresh instance per load.
  static func == (lhs: DocumentDownloadState, rhs: DocumentDownloadState) -> Bool {
    switch (lhs, rhs) {
    case (.initial, .initial), (.loading, .loading), (.error, .error):
      true
    case (.loaded(let lURL, let lDocument), .loaded(let rURL, let rDocument)):
      lURL == rURL && lDocument === rDocument
    default:
      false
    }
  }
}

/// Accumulates the errors thrown across one `DocumentDetailModel.load()` pass so
/// duplicates can be collapsed before they reach the caller's `onError`. Keyed on
/// `String(describing:)`: connectivity failures against the same host produce
/// equal `RequestError.other` values (identical description), so a server-wide
/// outage dedupes to a single entry, while distinct failures keep distinct keys.
@MainActor
private final class LoadErrorCollector {
  private var seen: Set<String> = []
  private(set) var distinct: [any Error] = []

  func add(_ error: any Error) {
    if seen.insert(String(describing: error)).inserted {
      distinct.append(error)
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

  /// The in-flight load, owned by the model rather than by whichever view task
  /// happened to start it. See `startLoad(onError:)`.
  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  init(
    store: DocumentStore, connection: Connection?, document: Document
  ) {
    self.store = store
    self.connection = connection
    self.document = document
  }

  /// Run `load` in a task owned by the model rather than by the caller's.
  ///
  /// A load must not be a structured child of the task that starts it, because
  /// both of the view's entry points have a lifetime shorter than the work:
  /// `.refreshable`'s task belongs to the pull gesture, and SwiftUI ends it when
  /// the scroll view's content changes underneath it. A refresh that picks up a
  /// new document version does exactly that — `loadDocument` swaps in the new
  /// PDF, the preview inside the scroll view is replaced, the refresh session
  /// ends, and the still-running metadata/notes/suggestions legs are cancelled
  /// mid-flight. The refresh cancels itself, and the user gets a "cancelled"
  /// toast for a refresh that silently didn't finish.
  ///
  /// An unstructured `Task` doesn't inherit cancellation (only priority and
  /// actor isolation), so the legs survive the gesture ending. View *dismissal*
  /// is still a real cancellation boundary — the view calls `cancelLoad()` on
  /// disappear — so a load whose result nobody will see still stops promptly,
  /// rather than surfacing a toast over whatever screen came next.
  func startLoad(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    // Latest wins: a pull-to-refresh supersedes an on-appear load still running.
    loadTask?.cancel()
    let task = Task { await self.load(onError: onError) }
    loadTask = task
    await task.value
  }

  /// Stop the in-flight load. The detail view calls this on dismissal — see
  /// ``startLoad(onError:)`` for why the load outlives the task that started it.
  func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
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
  /// The PDF itself doesn't wait for that metadata round-trip, though: on a
  /// fresh open, `loadDocument` fires a provisional download off the
  /// already-known (possibly stale) `document` in parallel with the metadata
  /// refresh, so a cached PDF renders immediately on a slow connection instead
  /// of sitting behind a blurred thumbnail.
  ///
  /// Once metadata comes back — on *every* load, not just a fresh open — the
  /// resolved document's version/`modified` is compared against what was on
  /// screen, and a changed one triggers a re-download. That is what makes a
  /// pull-to-refresh pick up a version added server-side while the detail view
  /// was open.
  ///
  /// Each step always logs its failure. Whether it's *surfaced* is the caller's
  /// choice via `onError`: an on-appear load (`.task`) passes nothing and stays
  /// silent (the load isn't user-initiated, and the one critical failure — the
  /// PDF — already shows via `download == .error`); a pull-to-refresh passes a
  /// handler so failures toast. Offline-connectivity errors are dropped by
  /// `ErrorController.shouldSuppress`, so a parallel offline refresh won't spam.
  ///
  /// The four steps each hit the network independently, so a server-wide outage
  /// would otherwise fire `onError` once per step — three or four identical
  /// "could not connect" toasts for a single pull. To avoid that, failures are
  /// collected across the whole pass and each *distinct* error is surfaced once:
  /// a common outage collapses to one toast, while genuinely different failures
  /// (e.g. a permission error on a single endpoint) still each show.
  func load(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    let collector = onError == nil ? nil : LoadErrorCollector()
    let collect: (@MainActor @Sendable (any Error) -> Void)?
    if let collector {
      collect = { @MainActor @Sendable error in collector.add(error) }
    } else {
      collect = nil
    }

    await loadDocument(onError: collect)
    async let metadata: Void = loadMetadata(onError: collect)
    async let notes: Void = loadNotes(onError: collect)
    async let suggestions: Void = loadSuggestionsQuietly(onError: collect)
    _ = await (metadata, notes, suggestions)

    if let onError, let collector {
      for error in collector.distinct {
        onError(error)
      }
    }
  }

  func loadMetadata(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    do {
      metadata = try await store.repository.metadata(documentId: document.id)
    } catch let error where error.isCancellationError {
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
    } catch let error where error.isCancellationError {
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
    } catch let error where error.isCancellationError {
    } catch {
      Logger.shared.error("Error loading document suggestions: \(error)")
      onError?(error)
    }
  }

  func loadDocument(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    let priorDocument = document
    let isFreshOpen = if case .initial = download { true } else { false }

    // Fire the provisional PDF load off the already-known document right away
    // — its own cache check (ContentStore, keyed on `currentVersionID` +
    // `modified`) is what decides whether this is an instant hit or a real
    // download, so starting it here rather than after the metadata round-trip
    // is what lets a cached PDF appear immediately on a slow connection.
    let provisionalDownload: Task<Void, Never>? =
      isFreshOpen ? Task { await runDownload(for: priorDocument) } : nil

    do {
      if let updated = try await store.document(id: document.id) {
        document = updated
      }
    } catch let error where error.isCancellationError {
    } catch {
      Logger.shared.error("Error updating document with full perms for editing: \(error)")
      onError?(error)
    }

    // Only the *provisional* download is fresh-open-only; on a refresh there
    // is nothing to wait for (`provisionalDownload` is nil) because the PDF is
    // already on screen.
    await provisionalDownload?.value

    // Nothing changed server-side — the PDF on screen (provisional or from a
    // previous load) already reflects current content, no need to re-fetch.
    //
    // The version check is what makes a server-side version bump visible: it
    // has to run on every load, not just a fresh open, or a document versioned
    // while the detail view is open keeps rendering the old file until the view
    // is closed and reopened. `runDownload` is safe to call here — its delayed
    // `.loading` flip is itself gated on `isFreshOpen`, so the new PDF swaps in
    // without blanking the preview.
    guard
      document.currentVersionID != priorDocument.currentVersionID
        || document.modified != priorDocument.modified
    else { return }

    await runDownload(for: document)
  }

  private func runDownload(for document: Document) async {
    let isFreshOpen = if case .initial = download { true } else { false }

    let setLoading =
      isFreshOpen
      ? Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        download = .loading
      } : nil
    // Cancel the delayed `.loading` flip on *every* exit path. Without this
    // the error path leaves `setLoading` pending, and 0.5s later it overwrites
    // the just-set `.error` back to `.loading` — pinning the preview's loading
    // overlay on screen even though the download already failed.
    defer { setLoading?.cancel() }
    do {
      let url = try await store.repository.download(
        document: document,
        original: false,
        progress: { @Sendable value in
          Task { @MainActor in
            self.downloadProgress = value
          }
        })

      if case .loaded(let existingURL, _) = download, existingURL == url {
        // Re-validation after the metadata refresh resolved to the same
        // cached file the provisional load already rendered — nothing to do.
        return
      }

      guard let pdfDocument = await PDFDocument.loadBackground(url: url) else {
        if case .loaded = download {} else { download = .error }
        return
      }

      download = .loaded(url: url, document: pdfDocument)

      // Start downloading the original in the background
      Task { await downloadOriginal() }
    } catch let error where error.isCancellationError {
    } catch {
      if case .loaded = download {
        // The provisional PDF is already on screen; keep showing it rather
        // than clobbering it with an error from the post-metadata re-check.
        Logger.shared.error("Unable to refresh document preview after metadata update: \(error)")
      } else {
        download = .error
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
      }
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

  // The server URL comes from the injected connection, not from downcasting
  // `store.repository`: the store holds a wrapper (`NeedsAuthRepository<ApiRepository>`),
  // so an `as? ApiRepository` cast silently fails and would drop the with-server link.
  var deepLinks: (withServer: Route?, withoutServer: Route?) {
    let withServer: Route? = connection.flatMap {
      guard let server = $0.url.stringDroppingScheme else { return nil }
      return Route(action: .document(id: document.id, edit: nil), server: server)
    }

    let withoutServer: Route? = Route(action: .document(id: document.id, edit: nil))
    return (withServer, withoutServer)

  }
}
