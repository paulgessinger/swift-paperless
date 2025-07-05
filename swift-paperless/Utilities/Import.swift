//
//  Import.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.04.2024.
//

import Foundation
import PDFKit
import PhotosUI
import SwiftUI
import UIKit
import os

// @TODO: UIImage not available on macOS

enum DocumentImportError: LocalizedError {
  case photosReceivalFailed
  case nilTransferableImage
  case imageRenderFailed
  case pdfWriteFailed
  case pdfCreatePageFailed

  var errorDescription: String? {
    switch self {
    case .photosReceivalFailed, .nilTransferableImage, .imageRenderFailed:
      String(localized: .localizable(.photosReceivalFailed))
    case .pdfCreatePageFailed:
      String(localized: .localizable(.documentScanErrorCreatePageFailed))
    case .pdfWriteFailed:
      String(localized: .localizable(.documentScanErrorWriteFailed))
    }
  }
}

@MainActor
func createPDFFrom(photos: [PhotosPickerItem]) async throws -> URL {
  Logger.shared.debug("Creating PDF from \(photos.count) PhotosPickerItems")
  var images: [UIImage] = []
  for item in photos {
    guard let image = try await item.loadTransferable(type: Image.self) else {
      Logger.shared.error("loadTransferableImage returned nil instead of image")
      throw DocumentImportError.nilTransferableImage
    }

    let renderer = ImageRenderer(content: image)

    guard let uiImage = renderer.uiImage else {
      Logger.shared.error("Image renderer returned nil instead of UIImage")
      throw DocumentImportError.imageRenderFailed
    }
    images.append(uiImage)
  }

  return try createPDFFrom(images: images)
}

func formattedImportFilename(prefix: String = "Scan") -> String {
  let date = Date().formatted(
    .verbatim(
      "\(year: .extended())-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .oneBased)).\(minute: .twoDigits).\(second: .twoDigits)",
      timeZone: TimeZone.current,
      calendar: .current
    ))

  return "\(prefix) \(date)"
}

func createPDFFrom(images: [UIImage]) throws -> URL {
  let pdfDocument = PDFDocument()
  for i in 0..<images.count {
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
