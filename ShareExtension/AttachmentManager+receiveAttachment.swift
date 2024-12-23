//
//  AttachmentManager+receiveAttachment.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 29.04.2024.
//

import os
import SwiftUI

private struct InvalidAttachmentContent: Error {}

extension AttachmentManager {
    private nonisolated
    static func loadItem(attachment: NSItemProvider, type: String) async throws -> URL {
        let data = try await attachment.loadItem(forTypeIdentifier: type, options: nil)

        Logger.shared.info("Loading item for type \(type, privacy: .public)")

        switch data {
        case let url as URL:
            Logger.shared.info("Received url \(url, privacy: .public)")
            return url

        case let data as NSData:
            Logger.shared.info("Received data length \(data.count) bytes, writing to temporary file")
            let mime = data.mimeType
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
            Logger.shared.info("Mapped mime \(mime, privacy: .public) to extension \(ext, privacy: .public)")

            let url = FileManager.default.temporaryDirectory
                .appending(component: formattedImportFilename(prefix: "Import"))
                .appendingPathExtension(ext)

            do {
                try data.write(to: url)
                return url
            } catch {
                Logger.shared.error("Unable to store data to temporary file: \(error, privacy: .public)")
                throw error
            }

        case let image as UIImage:
            Logger.shared.info("Received UIImage, saving as PNG")

            if let data = image.pngData() {
                let url = FileManager.default.temporaryDirectory
                    .appending(component: formattedImportFilename(prefix: "Import"))
                    .appendingPathExtension("png")
                do {
                    try data.write(to: url)
                    return url
                } catch {
                    Logger.shared.error("Unable to store data to temporary file: \(error, privacy: .public)")
                    throw error
                }
            } else {
                Logger.shared.error("Unable to convert image to PNG")
                throw InvalidAttachmentContent()
            }

        default:
            Logger.shared.error("Got attachment data \(String(describing: data), privacy: .public) but cannot handle")
            throw InvalidAttachmentContent()
        }
    }

    func receive(attachments: [NSItemProvider]) {
        Logger.shared.info("Receiving \(attachments.count) attachments")

        guard !attachments.isEmpty else {
            error = .noAttachments
            return
        }

        Task { @MainActor in
            for (idx, attachment) in attachments.enumerated() {
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
