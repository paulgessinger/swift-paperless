//
//  PaperlessIntentSupport.swift
//  swift-paperless
//

import AppIntents
import AppShared
import Foundation
import Networking
import Persistence
import UniformTypeIdentifiers
import os

enum PaperlessIntentError: LocalizedError {
  case noConnection
  case prepareFileFailed(String)
  case loadOptionsFailed(String)
  case missingElement(String)
  case uploadFailed(String)

  var errorDescription: String? {
    switch self {
    case .noConnection:
      String(localized: .app(.uploadDocumentIntentNoConnectionError))
    case .prepareFileFailed(let detail):
      String(localized: .app(.uploadDocumentIntentPrepareFileError(detail)))
    case .loadOptionsFailed(let detail):
      String(localized: .app(.uploadDocumentIntentLoadOptionsError(detail)))
    case .missingElement(let kind):
      String(localized: .app(.uploadDocumentIntentMissingElementError(kind)))
    case .uploadFailed(let detail):
      String(localized: .app(.uploadDocumentIntentUploadError(detail)))
    }
  }
}

/// The intents' view onto the process's ``AppStack``. Elements are read through
/// a `DocumentStore`, so results come from the local cache that `sync()` keeps
/// up to date.
///
/// The stack is emphatically *not* the intents' own. An intent declared in the
/// app target runs in the app's process, and `@main` builds the scene's
/// bootstrap on every launch — including the background launch the system does
/// to run this intent. Anything built here instead of borrowed would therefore
/// be a *second* database, second connection manager and second session
/// registry alongside the app's, on every run: observations that never see each
/// other's writes, two sessions racing the same server's sync, and a `server`
/// row cached twice. See ``AppStack`` for why each of those bites.
@MainActor
enum PaperlessIntentStore {
  private static var stack: AppStack {
    AppStackHolder.sharedWithInMemoryFallback(context: "Intents")
  }

  static var connectionManager: ConnectionManager { stack.connectionManager }

  private static var stores: [UUID: DocumentStore] = [:]

  static func store(server: PaperlessServerEntity? = nil) async throws -> DocumentStore {
    guard let id = server?.id ?? connectionManager.activeConnectionId,
      let stored = connectionManager.connections[id]
    else {
      throw PaperlessIntentError.noConnection
    }
    // Activating again is cheap when nothing changed, and rebuilds the stack
    // if the connection (e.g. its token) did since the store was created.
    let store = stores[id] ?? DocumentStore(registry: stack.sessionRegistry)
    try await store.activate(connection: stored, reload: false)
    stores[id] = store
    return store
  }
}

extension DocumentStore {
  /// Waits for an element sync for at most `timeout`. The sync keeps running
  /// past the deadline, and a failure is already swallowed by `sync()`, so
  /// callers just read whatever the cache holds afterwards.
  func sync(timeout: Duration) async {
    let (stream, continuation) = AsyncStream<Void>.makeStream()
    Task {
      try? await sync()
      continuation.yield()
    }
    let timer = Task {
      try? await Task.sleep(for: timeout)
      continuation.yield()
    }
    for await _ in stream { break }
    timer.cancel()
  }
}

struct PaperlessIntentUploadFile {
  let url: URL
  let filename: String
  let shouldRemoveAfterUpload: Bool

  static func materialize(_ file: IntentFile) throws -> Self {
    let filename = normalizedFilename(file.filename, type: file.type)

    if let url = file.fileURL {
      let isSecurityScoped = url.startAccessingSecurityScopedResource()
      defer {
        if isSecurityScoped {
          url.stopAccessingSecurityScopedResource()
        }
      }

      do {
        let copyURL = try temporaryUploadURL(filename: filename)
        do {
          try FileManager.default.copyItem(at: url, to: copyURL)
        } catch {
          try file.data.write(to: copyURL, options: .atomic)
        }

        return Self(url: copyURL, filename: filename, shouldRemoveAfterUpload: true)
      } catch {
        throw PaperlessIntentError.prepareFileFailed(error.localizedDescription)
      }
    }

    do {
      let url = try temporaryUploadURL(filename: filename)
      try file.data.write(to: url, options: .atomic)

      return Self(url: url, filename: filename, shouldRemoveAfterUpload: true)
    } catch {
      throw PaperlessIntentError.prepareFileFailed(error.localizedDescription)
    }
  }

  func cleanup() {
    guard shouldRemoveAfterUpload else { return }
    try? FileManager.default.removeItem(at: url)
  }

  private static func temporaryUploadURL(filename: String) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(
      path: "PaperlessShortcutUploads",
      directoryHint: .isDirectory)

    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true)

    return directory.appending(path: "\(UUID().uuidString)-\(filename)")
  }

  private static func normalizedFilename(_ filename: String, type: UTType?) -> String {
    let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
    let lastPathComponent = URL(fileURLWithPath: trimmed).lastPathComponent

    if !lastPathComponent.isEmpty {
      return lastPathComponent.precomposedStringWithCanonicalMapping
    }

    if let fileExtension = type?.preferredFilenameExtension {
      return "Document.\(fileExtension)"
    }

    return "Document"
  }
}
