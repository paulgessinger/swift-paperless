//
//  PDFView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.08.23.
//

import PDFKit
import SwiftUI

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    var displayMode = PDFDisplayMode.singlePageContinuous
    var pageShadows = true
    var autoScales = false
    var userInteraction = true
    var displayPageBreaks = true
    var pageBreakMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

//    @Binding private(set) var aspectRatio: CGFloat!

    func updateUIView(_: PDFKit.PDFView, context _: Context) {}

    func makeUIView(context _: Context) -> PDFKit.PDFView {
        let view = PDFKit.PDFView()
        view.autoScales = autoScales
        view.pageShadowsEnabled = pageShadows
        view.displayMode = displayMode
        view.document = document
        view.pageBreakMargins = pageBreakMargins
        view.displaysPageBreaks = displayPageBreaks

        view.isUserInteractionEnabled = userInteraction

        view.backgroundColor = .clear
        view.subviews[0].backgroundColor = UIColor.clear

//        view.autoresizesSubviews = true
//        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
//        view.maxScaleFactor = 4.0
//        view.minScaleFactor = 0.1
        return view
    }
}

struct PDFPreview: View {
    private let document: PDFDocument
    init?(file: URL) {
        guard let document = PDFDocument(url: file) else {
            return nil
        }
        self.document = document
    }

    var body: some View {
        PDFKitView(document: document,
                   displayMode: .singlePageContinuous,
                   pageShadows: false,
                   autoScales: true,
                   userInteraction: true)
    }
}

struct PDFThumbnail: View {
    private let document: PDFDocument
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

struct PDFPreview_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VStack {
                PDFPreview(file: Bundle.main.url(forResource: "demo2", withExtension: "pdf")!)
                    .edgesIgnoringSafeArea(.bottom)
                    .background(.gray)
                    .safeAreaInset(edge: .top) {}
            }
        }
    }
}
