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

  // Build a Database for the extension process. WAL allows concurrent
  // readers across processes, so opening the same app-group SQLite file
  // alongside the main app is supported. Cross-process live notification
  // is not — the extension sees whatever was committed at launch.
  // If the bootstrap fails (corrupt file, missing app-group), fall back to
  // an in-memory database so the extension still renders the disabled
  // "no active server" state cleanly instead of crashing.
  @StateObject private var connectionManager: ConnectionManager = {
    let database: Database
    do {
      database = try Database()
    } catch {
      Logger.shared.fault(
        "Share Extension database bootstrap failed (\(error)); falling back to in-memory")
      database =
        (try? Database.inMemory())
        ?? {
          // The in-memory path opens a DatabaseQueue and runs migrations,
          // both of which are infallible in practice. Force-unwrap so the
          // closure has a non-optional return; if this ever throws we want
          // to know immediately, not silently render a broken share sheet.
          preconditionFailure(
            "In-memory database fallback also failed; cannot construct ConnectionManager")
        }()
    }
    return ConnectionManager(database: database)
  }()

  @StateObject private var store = DocumentStore(repository: NullRepository())
  @State private var storeReady = false

  @StateObject private var errorController = ErrorController()

  @State private var error: String = ""

  var callback: () -> Void

  init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
    self.attachmentManager = attachmentManager
    self.callback = callback
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
        store.eventPublisher.send(.repositoryWillChange)
        await store.set(
          repository: ApiRepository(connection: conn, mode: Bundle.main.appConfiguration.mode))
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
                .environmentObject(store)
                .environmentObject(errorController)
                .environmentObject(connectionManager)
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
