//
//  DocumentDetailModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import DataModel
import Foundation
import SwiftUI
import os

enum DocumentDownloadState: Equatable {
  case initial
  case loading
  case loaded(URL)
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

  @ObservationIgnored
  var store: DocumentStore

  var document: Document

  // Not fully used by the edit model yet (I think we're loading suggestions twice right now)
  var suggestions: Suggestions?

  var metadata: Metadata?

  init(
    store: DocumentStore, document: Document
  ) {
    self.store = store
    self.document = document
  }

  func loadMetadata() async {
    do {
      metadata = try await store.repository.metadata(documentId: document.id)
    } catch is CancellationError {
    } catch {
      Logger.shared.error("Error loading document metadata: \(error)")
    }
  }

  func loadDocument() async {
    async let updated = try await store.document(id: document.id)

    switch download {
    case .initial:
      let setLoading = Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        download = .loading
      }
      do {
        guard
          let url = try await store.repository.download(
            documentID: document.id,
            progress: { @Sendable value in
              Task { @MainActor in
                self.downloadProgress = value
              }
            })
        else {
          download = .error
          break
        }

        download = .loaded(url)
        setLoading.cancel()
      } catch is CancellationError {
      } catch {
        download = .error
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
        break
      }

    default:
      break
    }

    do {
      if let updated = try await updated {
        document = updated
      }
    } catch {
      Logger.shared.error("Error updating document with full perms for editing: \(error)")
    }
  }

  func loadSuggestions() async throws {
    suggestions = try await store.repository.suggestions(documentId: document.id)
  }

  var userCanChange: Bool {
    store.userCanChange(document: document)
  }

  var userCanView: Bool {
    store.userCanView(document: document)
  }
}
