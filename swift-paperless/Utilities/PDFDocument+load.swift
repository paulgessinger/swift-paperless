//
//  PDFDocument+load.swift
//  swift-paperless
//

import Foundation
import PDFKit

extension PDFDocument {
  @concurrent
  static func loadBackground(url: URL) async -> sending PDFDocument? {
    return PDFDocument(url: url)
  }
}
