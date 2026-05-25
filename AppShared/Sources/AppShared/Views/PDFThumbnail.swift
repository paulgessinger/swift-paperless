//
//  PDFThumbnail.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.08.23.
//

import PDFKit
import SwiftUI

public struct PDFThumbnail: View {
  public let document: PDFDocument
  public let aspectRatio: CGFloat

  public let file: URL

  public let image: Image?

  public init?(file: URL) {
    self.file = file
    guard let document = PDFDocument(url: file) else {
      return nil
    }
    self.document = document
    let size: CGSize
    if let page = document.page(at: 0) {
      size = page.bounds(for: .trimBox).size
    } else {
      size = CGSize(width: 800, height: 800)
    }

    aspectRatio = CGFloat(size.width / size.height)

    image = document.thumbnailPNGData(pageIndex: 0, size: size)
      .flatMap { UIImage(data: $0) }
      .map { Image(uiImage: $0) }
  }

  public var body: some View {
    PDFKitView(
      document: document,
      displayMode: .singlePage,
      pageShadows: false,
      autoScales: true,
      userInteraction: false,
      displayPageBreaks: false,
      pageBreakMargins: .zero
    )

    .aspectRatio(aspectRatio, contentMode: .fill)
  }
}

public struct PDFThumbnail_Previews: PreviewProvider {
  public static var previews: some View {
    NavigationStack {
      VStack {
        PDFThumbnail(file: Bundle.main.url(forResource: "demo2", withExtension: "pdf")!)
          .frame(width: 200, height: 200, alignment: .top)
          .background(.green)
          .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
          .shadow(radius: 10)
      }
    }
  }
}
