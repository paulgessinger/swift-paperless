//
//  PDFKitView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.05.2024.
//

import Foundation
import PDFKit
import SwiftUI

public struct PDFKitView: UIViewRepresentable {
  public let document: PDFDocument

  public var displayMode = PDFDisplayMode.singlePageContinuous
  public var pageShadows = true
  public var autoScales = false
  public var userInteraction = true
  public var displayPageBreaks = true
  public var pageBreakMargins = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15)

  public var minScaleFactor: CGFloat?
  public var maxScaleFactor: CGFloat?
  public var scaleFactor: CGFloat?

  public var pageIndex: Int?

  public init(
    document: PDFDocument,
    displayMode: PDFDisplayMode = .singlePageContinuous,
    pageShadows: Bool = true,
    autoScales: Bool = false,
    userInteraction: Bool = true,
    displayPageBreaks: Bool = true,
    pageBreakMargins: UIEdgeInsets = UIEdgeInsets(top: 15, left: 15, bottom: 15, right: 15),
    minScaleFactor: CGFloat? = nil,
    maxScaleFactor: CGFloat? = nil,
    scaleFactor: CGFloat? = nil,
    pageIndex: Int? = nil
  ) {
    self.document = document
    self.displayMode = displayMode
    self.pageShadows = pageShadows
    self.autoScales = autoScales
    self.userInteraction = userInteraction
    self.displayPageBreaks = displayPageBreaks
    self.pageBreakMargins = pageBreakMargins
    self.minScaleFactor = minScaleFactor
    self.maxScaleFactor = maxScaleFactor
    self.scaleFactor = scaleFactor
    self.pageIndex = pageIndex
  }

  public func updateUIView(_: PDFKit.PDFView, context _: Context) {}

  public func makeUIView(context _: Context) -> PDFKit.PDFView {
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
