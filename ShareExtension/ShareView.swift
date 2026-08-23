//
//  ShareView.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 29.04.2024.
//

import AppShared
import Networking
import Persistence
import SwiftUI
import os

struct ShareView: View {
  @ObservedObject var attachmentManager: AttachmentManager

  @State private var connectionManager: ConnectionManager
  @State private var store: DocumentStore
  @State private var storeReady = false

  @StateObject private var errorController = ErrorController()

  @State private var presentedError: (any DisplayableError)?

  var callback: () -> Void

  init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
    self.attachmentManager = attachmentManager
    self.callback = callback
    // The extension process's own Database (app-group SQLite, WAL). The same DB
    // backs the `ConnectionManager` and — through the session's
    // `CachingRepository` — the element cache, so the store's `ElementStore`
    // projection observes the extension's own writes. Cross-process live
    // notification isn't delivered (the extension syncs at launch), but the
    // extension's in-process writes drive its own observation normally.
    let database = Self.bootstrapDatabase()
    let connectionManager = ConnectionManager(database: database)
    _connectionManager = State(initialValue: connectionManager)
    // The extension keeps the same one-session-per-server rule as the app, in a
    // process that has no `SyncEngine` to share those sessions with. The registry
    // is retained by the store; it is never `start()`ed, because an extension has
    // no reason to react to connection edits made elsewhere.
    _store = State(
      initialValue: DocumentStore(
        registry: ServerSessionRegistry(database: database, manager: connectionManager)))
  }

  // Open the app-group SQLite file. If the bootstrap fails (corrupt file,
  // missing app-group), fall back to an in-memory database so the extension
  // still renders the disabled "no active server" state cleanly instead of
  // crashing. The in-memory path (DatabaseQueue + migrations) is infallible in
  // practice; if it ever throws we want to know immediately — but log the
  // fallback's own error first, since `preconditionFailure` only carries its
  // message into the crash report and the underlying error is the only thing
  // that would make such a report diagnosable.
  private static func bootstrapDatabase() -> Database {
    do {
      return try Database()
    } catch {
      Logger.shared.fault(
        "Share Extension database bootstrap failed (\(error)); falling back to in-memory")
      do {
        return try Database.inMemory()
      } catch {
        Logger.shared.fault(
          "Share Extension in-memory database fallback also failed: \(error)")
        preconditionFailure(
          "In-memory database fallback also failed (\(error)); cannot construct ConnectionManager")
      }
    }
  }

  // Matched on the error rather than `ConnectionManager`'s `needsAuth` flag:
  // that flag is set through a database write, and this has to be right on the
  // frame the alert is built.
  private func isUnauthorized(_ error: any Error) -> Bool {
    if let request = error as? RequestError, case .unauthorized = request {
      return true
    }
    return false
  }

  private func internalCallback() {
    if !attachmentManager.importUrls.isEmpty {
      attachmentManager.importUrls.removeFirst()
    }
    Logger.shared.info("Document created \(attachmentManager.importUrls) inputs left")
    if attachmentManager.importUrls.isEmpty {
      callback()
    }
  }

  private func refreshConnection() {
    Logger.api.info("Connection info changed, reloading!")

    if let stored = connectionManager.storedConnection {
      Logger.api.trace("Valid connection from connection manager: \(stored.logLabel)")
      Task {
        store.events.emit(.repositoryWillChange)
        // Caching outermost, over the extension's own DB, so the store's
        // ElementStore projection observes the writes its sync performs. The
        // server's session owns that assembly (see `DocumentStore.activate`), so
        // the extension can't drift from the app's layering.
        do {
          try await store.activate(connection: stored)
        } catch {
          Logger.api.error("Could not build repository for active connection: \(error)")
          return
        }
        storeReady = true
        try? await store.sync()
      }
    } else {
      Logger.shared.trace("App does not have any active connection")
    }
  }

  private var createTitle: String {
    let remaining = attachmentManager.totalInputs - attachmentManager.importUrls.count + 1
    Logger.shared.info(
      "Creating share sheet title: totalInputs: \(attachmentManager.totalInputs) importURLs: \(attachmentManager.importUrls.count) -> remaining \(remaining)"
    )
    // Apparently sometimes this is 0 (odd), hide the x/y title in that case
    if attachmentManager.totalInputs <= 1 {
      return String(localized: .app(.documentAdd))
    } else {
      return
        "\(String(localized: .app(.documentAdd))) (\(remaining) / \(attachmentManager.totalInputs))"
    }
  }

  @ScaledMetric(relativeTo: .title) private var emojiScale = 50.0

  func errorView(_: AttachmentError) -> some View {
    VStack {
      Text(.app(.shareSheetInvalidAttachmentTitle))
        .font(.title)
        .padding()
      Text("🫣")
        .font(.system(size: emojiScale))

      Text(.app(.shareSheetInvalidAttachmentDetail))
        .multilineTextAlignment(.center)
        .padding(.top)

      LogRecordExportButton()
        .foregroundColor(.white)
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
        .background {
          RoundedRectangle(cornerRadius: 15)
            .fill(Color.accentColor)
        }
        .padding(.top, 30)
      //                            .buttonStyle(.borderedProminent)
    }
    .padding()
    .accentColor(Color(.accent))
  }

  var body: some View {
    Group {
      if connectionManager.connection != nil {
        if let error = attachmentManager.error {
          errorView(error)
        } else {
          if let url = attachmentManager.importUrls.first {
            VStack {
              if storeReady {
                CreateDocumentView(
                  sourceUrl: url,
                  callback: internalCallback,
                  share: true,
                  title: createTitle
                )
                .id(url)
                // @FIXME: Gives a white band at the bottom, not ideal
                .padding(.bottom, 40)
                .environment(store)
                .environmentObject(errorController)
                .environment(connectionManager)
                .accentColor(Color(.accent))
              } else {
                ProgressView()
              }
            }
            .animation(.default, value: storeReady)
          }
        }
      } else {
        VStack {
          Spacer()
          HStack {
            Spacer()
            Text(.app(.shareSheetNotLoggedIn))
              .foregroundColor(.gray)
              .multilineTextAlignment(.center)
            Spacer()
          }
          Spacer()
        }
      }
    }

    .task {
      refreshConnection()
    }

    .onChange(of: connectionManager.activeConnectionId) { refreshConnection() }
    .onChange(of: connectionManager.connections) { refreshConnection() }

    // Without this the `errorController` above has no subscriber at all and
    // every push — an upload rejected for a 401 included — is dropped by the
    // PassthroughSubject, leaving only the toolbar's three-second warning
    // triangle.
    //
    // The app's toast surface can't be reused: `installToast` renders into a
    // full-screen window inset by the safe area of its *host* view, which is
    // ~0 inside the share sheet, so the toast lands under the Dynamic Island.
    // An alert is positioned by the system, and the extension is a single
    // screen with no competing presentation to conflict with.
    .onReceive(errorController.presentations) { presentedError = $0 }
    .alert(
      unwrapping: $presentedError,
      // Resolved with `String(localized:)` rather than handed to `Text` as a
      // `LocalizedStringResource`: in the alert title slot the resource is
      // stringified with its attributes still attached, rendering as
      // `Sign in again{ NSLanguage = en; }`.
      title: { error in
        if isUnauthorized(error) {
          Text(String(localized: .app(.shareSheetNeedsAuthTitle)))
        } else {
          Text(error.message)
        }
      },
      actions: { ErrorAlertActions(for: $0) },
      // An expired login is the one failure the user can act on — but not from
      // here. `NeedsAuthRepository` flips the connection's flag, but the
      // recovery UI lives in the app target, and `NSExtensionContext.open`
      // does nothing from a share extension, so refer them to the app.
      message: { error in
        if isUnauthorized(error) {
          Text(String(localized: .app(.shareSheetNeedsAuthMessage)))
        } else if let details = error.details {
          Text(details)
        }
      }
    )
  }
}
