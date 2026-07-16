//
//  PaperlessIntentSupport.swift
//  swift-paperless
//

import AppIntents
import AppShared
import Foundation
import Networking
import UniformTypeIdentifiers

enum PaperlessIntentError: LocalizedError {
  case noConnection
  case prepareFileFailed(String)
  case loadOptionsFailed(String)
  case uploadFailed(String)

  var errorDescription: String? {
    switch self {
    case .noConnection:
      String(localized: .app(.uploadDocumentIntentNoConnectionError))
    case .prepareFileFailed(let detail):
      String(localized: .app(.uploadDocumentIntentPrepareFileError(detail)))
    case .loadOptionsFailed(let detail):
      String(localized: .app(.uploadDocumentIntentLoadOptionsError(detail)))
    case .uploadFailed(let detail):
      String(localized: .app(.uploadDocumentIntentUploadError(detail)))
    }
  }
}

enum PaperlessIntentRepository {
  @MainActor
  static func repository(server: PaperlessServerEntity? = nil) async throws -> ApiRepository {
    if let server {
      return try await ApiRepository(
        connection: server.connection.connection, mode: Bundle.main.appConfiguration.mode)
    }

    let connectionManager = ConnectionManager()
    guard let connection = connectionManager.connection else {
      throw PaperlessIntentError.noConnection
    }

    return await ApiRepository(connection: connection, mode: Bundle.main.appConfiguration.mode)
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
