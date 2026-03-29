//
//  AttachmentManager+receiveAttachment.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 29.04.2024.
//

import SwiftUI
import os

private struct InvalidAttachmentContent: Error {}

extension AttachmentManager {
  private enum LoadedItem: Sendable {
    case url(URL)
    case data(Data)
    case image(UIImage)
  }

  @MainActor
  private static func loadItemFromProvider(attachment: NSItemProvider, type: String) async throws
    -> LoadedItem
  {
    let data = try await attachment.loadItem(forTypeIdentifier: type, options: nil)
    Logger.shared.info("Loading item for type \(type, privacy: .public)")

    switch data {
    case let url as URL:
      Logger.shared.info("Received url \(url, privacy: .public)")
      return .url(url)

    case let data as NSData:
      Logger.shared.info("Received data length \(data.count) bytes")
      return .data(data as Data)

    case let image as UIImage:
      Logger.shared.info("Received UIImage")
      return .image(image)

    default:
      Logger.shared.error(
        "Got attachment data \(String(describing: data), privacy: .public) but cannot handle")
      throw InvalidAttachmentContent()
    }
  }

  private nonisolated static func processLoadedItem(_ item: LoadedItem) throws -> URL {
    switch item {
    case .url(let url):
      return url

    case .data(let data):
      let mime = (data as NSData).mimeType
      Logger.shared.info("Got mime type \(mime, privacy: .public)")

      let ext: String
      switch mime {
      case "application/pdf":
        ext = "pdf"
      case "image/png":
        ext = "png"
      case "image/jpeg":
        ext = "jpg"
      case "image/gif":
        ext = "gif"
      default:
        Logger.shared.error("Got mime type \(mime, privacy: .public) but cannot handle")
        throw InvalidAttachmentContent()
      }

      Logger.shared.info(
        "Mapped mime \(mime, privacy: .public) to extension \(ext, privacy: .public)")
      let url = FileManager.default.temporaryDirectory
        .appending(component: formattedImportFilename(prefix: "Import"))
        .appendingPathExtension(ext)
      try data.write(to: url)
      return url

    case .image(let image):
      let url = FileManager.default.temporaryDirectory
        .appending(component: formattedImportFilename(prefix: "Import"))
        .appendingPathExtension("png")
      guard let data = image.pngData() else {
        Logger.shared.error("Unable to convert image to PNG")
        throw InvalidAttachmentContent()
      }
      try data.write(to: url)
      return url
    }
  }

  private static func loadItem(attachment: NSItemProvider, type: String) async throws -> URL {
    let item = try await loadItemFromProvider(attachment: attachment, type: type)
    return try await Task.detached {
      try processLoadedItem(item)
    }.value
  }

  func receive(attachments: sending [NSItemProvider]) {
    Logger.shared.info("Receiving \(attachments.count) attachments")

    guard !attachments.isEmpty else {
      error = .noAttachments
      return
    }

    let items = attachments
    Task { @MainActor in
      for (idx, attachment) in items.enumerated() {
        Logger.shared.info("- #\(idx) ~> \(String(describing: attachment), privacy: .public)")
        if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
          Logger.shared.info("Attachment has type PDF")
          do {
            let url = try await Self.loadItem(attachment: attachment, type: "com.adobe.pdf")
            importUrls.append(url)
            totalInputs = totalInputs + 1
            Logger.shared.info("Total inputs now: \(self.totalInputs)")
          } catch {
            Logger.shared.error("Error getting PDF attachment: \(error)")
            self.error = .invalidAttachment
          }
        }

        if attachment.hasItemConformingToTypeIdentifier("public.image") {
          Logger.shared.info("Attachment has type image")
          do {
            let url = try await Self.loadItem(attachment: attachment, type: "public.image")
            importUrls.append(url)
            totalInputs = totalInputs + 1
            Logger.shared.info("Total inputs now: \(self.totalInputs)")
          } catch {
            Logger.shared.error("Error getting Image attachment: \(error)")
            self.error = .invalidAttachment
          }
        }
      }
    }
  }
}
