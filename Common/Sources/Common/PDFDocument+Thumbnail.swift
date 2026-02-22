import Foundation
import PDFKit

#if canImport(UIKit)
  import UIKit
#elseif canImport(AppKit)
  import AppKit
#endif

extension PDFDocument {
  /// Renders a PNG thumbnail for a page of the PDF.
  /// Returns `nil` if the page is missing or conversion fails.
  public func thumbnailPNGData(
    pageIndex: Int = 0,
    size: CGSize = CGSize(width: 360, height: 480),
    box: PDFDisplayBox = .mediaBox
  ) -> Data? {
    guard let page = page(at: pageIndex) else { return nil }
    let thumbnail = page.thumbnail(of: size, for: box)

    #if canImport(UIKit)
      return thumbnail.pngData()
    #elseif canImport(AppKit)
      guard
        let tiff = thumbnail.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
      else {
        return nil
      }
      return rep.representation(using: .png, properties: [:])
    #else
      return nil
    #endif
  }
}
