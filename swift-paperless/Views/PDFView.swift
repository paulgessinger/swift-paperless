//
//  PDFView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.08.23.
//

import PDFKit
import SwiftUI

struct PDFThumbnail: View {
    let document: PDFDocument
    let aspectRatio: CGFloat

    let file: URL

    init?(file: URL) {
        self.file = file
        guard let document = PDFDocument(url: file) else {
            return nil
        }
        self.document = document
        let bounds = document.page(at: 0)?.bounds(for: .trimBox)
        if let bounds {
            aspectRatio = CGFloat(bounds.width / bounds.height)
        } else {
            aspectRatio = 1
        }
    }

    var body: some View {
        PDFKitView(document: document,
                   displayMode: .singlePage,
                   pageShadows: false,
                   autoScales: true,
                   userInteraction: false,
                   displayPageBreaks: false,
                   pageBreakMargins: .zero)

            .aspectRatio(aspectRatio, contentMode: .fill)
    }
}

struct PDFView_Previews: PreviewProvider {
    static var previews: some View {
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
