//
//  Import.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.2024.
//

import Foundation
import os
import PDFKit
import PhotosUI
import SwiftUI
import UIKit

// @TODO: UIImage not available on macOS

enum DocumentImportError: LocalizedError {
    case photosReceivalFailed
    case pdfWriteFailed
    case pdfCreatePageFailed

    var errorDescription: String? {
        switch self {
        case .photosReceivalFailed:
            return String(localized: .localizable.photosReceivalFailed)
        case .pdfCreatePageFailed:
            return String(localized: .localizable.documentScanErrorCreatePageFailed)
        case .pdfWriteFailed:
            return String(localized: .localizable.documentScanErrorWriteFailed)
        }
    }
}

// Somehow, this avoids PhotosPickerItem to have to be sendable, which it isn't
@MainActor
private func loadTransferableImage(item: PhotosPickerItem) async throws -> Image? {
    try await withCheckedThrowingContinuation { continuation in
        item.loadTransferable(type: Image.self) { result in
            switch result {
            case let .success(image):
                continuation.resume(returning: image)
            case let .failure(error):
                continuation.resume(throwing: error)
            }
        }
    }
}

@MainActor
func createPDFFrom(photos: [PhotosPickerItem]) async throws -> URL {
    Logger.shared.debug("Creating PDF from \(photos.count) PhotosPickerItems")
    var images: [UIImage] = []
    for item in photos {
        guard let image = try await loadTransferableImage(item: item) else {
            throw DocumentImportError.photosReceivalFailed
        }

        let renderer = ImageRenderer(content: image)

        guard let uiImage = renderer.uiImage else {
            throw DocumentImportError.photosReceivalFailed
        }
        images.append(uiImage)
    }

    return try createPDFFrom(images: images)
}

func formattedImportFilename(prefix: String = "Scan") -> String {
    let date = Date().formatted(.verbatim(
        "\(year: .extended())-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits)",
        timeZone: TimeZone.current,
        calendar: .current
    ))

    return "\(prefix) \(date)"
}

func createPDFFrom(images: [UIImage]) throws -> URL {
    let pdfDocument = PDFDocument()
    for i in 0 ..< images.count {
        if let pdfPage = PDFPage(image: images[i]) {
            pdfDocument.insert(pdfPage, at: i)
        } else {
            throw DocumentImportError.pdfCreatePageFailed
        }
    }

    let url = FileManager.default.temporaryDirectory
        .appending(component: formattedImportFilename())
        .appendingPathExtension("pdf")

    if pdfDocument.write(to: url) {
        return url
    } else {
        throw DocumentImportError.pdfWriteFailed
    }
}
