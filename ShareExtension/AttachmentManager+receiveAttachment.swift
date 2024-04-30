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
    private enum Item {
        case url(_: URL)
        case image(_: UIImage)
    }

    private static func loadItem(attachment: NSItemProvider, type: String) async throws -> Item {
        try await withCheckedThrowingContinuation { continuation in
            Logger.shared.info("Loading item for type \(type, privacy: .public)")
            attachment.loadItem(forTypeIdentifier: type, options: nil, completionHandler: { data, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                switch data {
                case let url as URL:
                    Logger.shared.info("Received url \(url, privacy: .public)")
                    if type == "public.image" {
                        Logger.shared.info("Expected type is public.image, load UIImage from URL")
                        do {
                            if let image = try UIImage(data: Data(contentsOf: url)) {
                                continuation.resume(returning: .image(image))
                            } else {
                                Logger.shared.error("Unable to load content of URL as UIImage")
                                continuation.resume(throwing: InvalidAttachmentContent())
                            }
                        } catch {
                            Logger.shared.error("Unable to load data from URL")
                            continuation.resume(throwing: error)
                        }
                    } else {
                        continuation.resume(returning: .url(url))
                    }
                case let data as NSData:
                    Logger.shared.info("Received data length \(data.count) bytes")
                    let mime = data.mimeType

                    if type == "com.adobe.pdf" {
                        if mime != "application/pdf" {
                            Logger.shared.error("Received item of type com.adobe.pdf but mime was \(mime, privacy: .public)")
                            continuation.resume(throwing: InvalidAttachmentContent())
                        } else {
                            Logger.shared.info("Received PDF input as NSData, writing to temporary file")
                            let url = FileManager.default.temporaryDirectory
                                .appending(component: formattedImportFilename(prefix: "Import"))
                                .appendingPathExtension("pdf")
                            do {
                                try data.write(to: url)
                                continuation.resume(returning: .url(url))
                            } catch {
                                Logger.shared.error("Unable to store data to temporary file")
                            }
                        }
                    } else if type != "public.image" {
                        Logger.shared.info("Received Image input as NSData")
                        if let image = UIImage(data: Data(referencing: data)) {
                            continuation.resume(returning: .image(image))
                        } else {
                            Logger.shared.error("Received supposed image as NSData, but could not create UIImage")
                            continuation.resume(throwing: InvalidAttachmentContent())
                            return
                        }
                    } else {
                        Logger.shared.error("Unknown item type received")
                        continuation.resume(throwing: InvalidAttachmentContent())
                    }

                case let image as UIImage:
                    Logger.shared.info("Received UIImage")
                    continuation.resume(returning: .image(image))

                default:
                    Logger.shared.error("Got attachment data \(String(describing: data), privacy: .public) but cannot handle")
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

        Logger.shared.info("Receiving \(attachments.count) attachments")

        Task {
            var images: [UIImage] = []

            for attachment in attachments {
                if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                    Logger.shared.info("Attachment has type PDF")
                    do {
                        switch try await Self.loadItem(attachment: attachment, type: "com.adobe.pdf") {
                        case let .url(url):
                            importUrls.append(url)
                        default:
                            Logger.shared.error("Loaded com.adobe.pdf but did not receive a url")
                            throw InvalidAttachmentContent()
                        }
                    } catch {
                        Logger.shared.error("Error getting PDF attachment: \(error)")
                        self.error = .invalidAttachment
                    }
                }

                if attachment.hasItemConformingToTypeIdentifier("public.image") {
                    Logger.shared.info("Attachment has type image")
                    do {
                        switch try await Self.loadItem(attachment: attachment, type: "public.image") {
                        case let .image(image):
                            images.append(image)
                        default:
                            Logger.shared.error("Loaded public.image but did not receive UIImage")
                            throw InvalidAttachmentContent()
                        }
                    } catch {
                        Logger.shared.error("Error getting Image attachment: \(error)")
                        self.error = .invalidAttachment
                    }
                }
            }

            if !images.isEmpty {
                do {
                    let pdf = try createPDFFrom(images: images)
                    Logger.shared.info("Created PDF from \(images.count) images")
                    importUrls.append(pdf)
                } catch {
                    Logger.shared.error("Could not create PDF from images: \(error)")
                }
            }
        }
    }
}
