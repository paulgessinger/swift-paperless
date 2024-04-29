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
    private static func loadItem(attachment: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: type, options: nil, completionHandler: { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                switch data {
                case let url as URL:
                    Logger.shared.info("Received url \(url)")
                    continuation.resume(returning: url)
                default:
                    Logger.shared.error("Got attachment data \(String(describing: data)) but cannot handle")
                    continuation.resume(throwing: InvalidAttachmentContent())
                }
            })
        }
    }

    func receive(attachments: [NSItemProvider]) {
        guard !attachments.isEmpty else {
            error = .noAttachments
            return
        }

        Logger.shared.notice("Receiving \(attachments.count) attachments")

        Task {
            var images: [UIImage] = []

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                    Logger.shared.notice("Attachment has type PDF")
                    do {
                        let url = try await Self.loadItem(attachment: attachment, type: "com.adobe.pdf")
                        importUrls.append(url)
                    } catch {
                        Logger.shared.error("Error getting PDF attachment")
                        self.error = .invalidAttachment
                    }
                }

                if attachment.hasItemConformingToTypeIdentifier("public.image") {
                    Logger.shared.notice("Attachment has type image")
                    do {
                        let url = try await Self.loadItem(attachment: attachment, type: "public.image")
                        Logger.shared.notice("URL is \(url)")
                        let data = try Data(contentsOf: url)
                        if let image = UIImage(data: data) {
                            images.append(image)
                        } else {
                            Logger.shared.error("Image at \(url) could not be loaded")
                            self.error = .invalidImage
                            return
                        }
                    } catch {
                        Logger.shared.error("Error getting Image attachment: \(error)")
                        self.error = .invalidAttachment
                    }
                }
            }

            do {
                let pdf = try createPDFFrom(images: images)
                Logger.shared.notice("Created PDF from \(images.count) images")
                importUrls.append(pdf)
            } catch {
                Logger.shared.error("Could not create PDF from images: \(error)")
            }
        }
    }
}
