//
//  KeepSavedViewOffline.swift
//  swift-paperless
//

import AppShared
import Common
import DataModel
import SwiftUI
import os

/// A saved view the user asked to keep offline, waiting for confirmation.
struct KeepOfflineRequest {
  let savedView: SavedView
  /// The documents its cached list holds; `nil` if it was never opened.
  let documentCount: UInt?
}

/// "Keep offline" or "Stop keeping offline" for a saved view. Stopping
/// happens at once; keeping puts a request in `request`, which
/// ``SwiftUICore/View/keepSavedViewOfflineConfirmation(_:)`` confirms. The
/// confirmation sits outside the button because the button is usually a menu
/// item. Reads the kept state itself, so a toggle redraws only the button.
struct KeepSavedViewOfflineButton: View {
  @Environment(DocumentStore.self) private var store
  @EnvironmentObject private var errorController: ErrorController
  let savedView: SavedView
  @Binding var request: KeepOfflineRequest?

  var body: some View {
    Button {
      Task {
        if store.isKeptOffline(savedView: savedView.id) {
          await setKeptOffline(savedView, false, store: store, errorController: errorController)
        } else {
          let count = await store.cachedDocumentCount(savedView: savedView)
          request = KeepOfflineRequest(savedView: savedView, documentCount: count)
        }
      }
    } label: {
      if store.isKeptOffline(savedView: savedView.id) {
        Label(
          String(localized: .app(.stopKeepingSavedViewOffline)),
          systemImage: "arrow.down.circle.fill")
      } else {
        Label(String(localized: .app(.keepSavedViewOffline)), systemImage: "arrow.down.circle")
      }
    }
  }
}

extension View {
  /// Asks before keeping the saved view in `request` offline: a view can list
  /// thousands of documents.
  func keepSavedViewOfflineConfirmation(_ request: Binding<KeepOfflineRequest?>) -> some View {
    modifier(KeepSavedViewOfflineConfirmation(request: request))
  }
}

private struct KeepSavedViewOfflineConfirmation: ViewModifier {
  @Environment(DocumentStore.self) private var store
  @EnvironmentObject private var errorController: ErrorController
  @Binding var request: KeepOfflineRequest?

  func body(content: Content) -> some View {
    content
      .confirmationDialog(
        request.map {
          String(localized: .app(.keepSavedViewOfflineTitle($0.savedView.name)))
        } ?? "",
        isPresented: Binding(
          get: { request != nil },
          set: { if !$0 { request = nil } }),
        titleVisibility: .visible,
        presenting: request
      ) { request in
        Button(String(localized: .app(.keepSavedViewOffline))) {
          Task {
            await setKeptOffline(
              request.savedView, true, store: store, errorController: errorController)
          }
        }
        Button(String(localized: .app(.cancel)), role: .cancel) {}
      } message: { request in
        if let count = request.documentCount {
          Text(.app(.keepSavedViewOfflineMessageCount(Int(count))))
        } else {
          Text(.app(.keepSavedViewOfflineMessage))
        }
      }
  }
}

@MainActor
private func setKeptOffline(
  _ savedView: SavedView, _ kept: Bool, store: DocumentStore, errorController: ErrorController
) async {
  do {
    try await store.setKeptOffline(savedView: savedView, kept)
  } catch {
    Logger.shared.error("Keeping a saved view offline failed: \(error)")
    errorController.push(error: error)
  }
}
