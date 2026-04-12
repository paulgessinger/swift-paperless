//
//  PDFKitView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.2024.
//

import Foundation
import PDFKit
import SwiftUI

struct PDFKitView: UIViewRepresentable {
  let document: PDFDocument

  var displayMode = PDFDisplayMode.singlePageContinuous
  var pageShadows = true
  var autoScales = false
  var userInteraction = true
  var displayPageBreaks = true
  var pageBreakMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

  var minScaleFactor: CGFloat?
  var maxScaleFactor: CGFloat?
  var scaleFactor: CGFloat?

  var pageIndex: Int?

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

    if let minScaleFactor {
      view.minScaleFactor = minScaleFactor
    }
    if let maxScaleFactor {
      view.maxScaleFactor = maxScaleFactor
    }
    if let scaleFactor {
      view.scaleFactor = scaleFactor
    }

    if let pageIndex, let page = document.page(at: pageIndex) {
      view.go(to: page)
    }

    return view
  }
}
