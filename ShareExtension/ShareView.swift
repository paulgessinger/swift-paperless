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

  // The extension process's own Database (app-group SQLite, WAL). The same DB
  // backs the `ConnectionManager` and — wrapped in a `CachingRepository` in
  // `refreshConnection` — the element cache, so the store's `ElementStore`
  // projection observes the extension's own writes. Cross-process live
  // notification isn't delivered (the extension syncs at launch), but the
  // extension's in-process writes drive its own observation normally.
  private let database: Database

  @State private var connectionManager: ConnectionManager
  @State private var store = DocumentStore(repository: NullRepository())
  @State private var storeReady = false

  @StateObject private var errorController = ErrorController()

  @State private var error: String = ""

  var callback: () -> Void

  init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
    self.attachmentManager = attachmentManager
    self.callback = callback
    let database = Self.bootstrapDatabase()
    self.database = database
    _connectionManager = State(initialValue: ConnectionManager(database: database))
  }

  // Open the app-group SQLite file. If the bootstrap fails (corrupt file,
  // missing app-group), fall back to an in-memory database so the extension
  // still renders the disabled "no active server" state cleanly instead of
  // crashing. The in-memory path (DatabaseQueue + migrations) is infallible in
  // practice; if it ever throws we want to know immediately.
  private static func bootstrapDatabase() -> Database {
    do {
      return try Database()
    } catch {
      Logger.shared.fault(
        "Share Extension database bootstrap failed (\(error)); falling back to in-memory")
      if let inMemory = try? Database.inMemory() {
        return inMemory
      }
      preconditionFailure(
        "In-memory database fallback also failed; cannot construct ConnectionManager")
    }
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

    if let conn = connectionManager.connection {
      Logger.api.trace("Valid connection from connection manager: \(String(describing: conn))")
      Task {
        store.events.emit(.repositoryWillChange)
        // Caching outermost, over the extension's own DB, so the store's
        // ElementStore projection observes the writes its sync performs.
        let api = await ApiRepository(connection: conn, mode: Bundle.main.appConfiguration.mode)
        let needsAuth = NeedsAuthRepository(
          wrapping: api, serverID: conn.serverID, connectionManager: connectionManager)
        let repository = CachingRepository(
          wrapping: needsAuth, database: database, serverID: conn.serverID)
        store.set(repository: repository)
        storeReady = true
        try? await store.fetchAll()
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
  }
}
