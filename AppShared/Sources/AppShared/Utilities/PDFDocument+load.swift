//
//  PDFDocument+load.swift
//  swift-paperless
//

import Foundation
import PDFKit

extension PDFDocument {
  @concurrent
  public static func loadBackground(url: URL) async -> sending PDFDocument? {
    return PDFDocument(url: url)
  }

  /// Reads the whole file up front, so the document stays intact if the file
  /// is replaced while it is on screen.
  @concurrent
  public static func loadBackgroundInMemory(url: URL) async -> sending PDFDocument? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return PDFDocument(data: data)
  }
}
