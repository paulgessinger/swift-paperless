//
//  HFlow.swift
//  swift-paperless
//
//  Created by Codex on 29.03.26.
//

import SwiftUI

struct HFlow: Layout {
  enum VerticalAlignment {
    case top
    case center
    case bottom
  }

  var itemSpacing: CGFloat?
  var rowSpacing: CGFloat?
  var verticalAlignment: VerticalAlignment = .top

  private struct Row {
    struct Item {
      let index: Int
      let size: CGSize
      let x: CGFloat
    }

    var items: [Item]
    var width: CGFloat
    var height: CGFloat
  }

  private func resolvedItemSpacing() -> CGFloat {
    itemSpacing ?? 8
  }

  private func resolvedRowSpacing() -> CGFloat {
    rowSpacing ?? itemSpacing ?? 8
  }

  private func measure(
    subview: LayoutSubview,
    proposal: ProposedViewSize,
    maxWidth: CGFloat?
  ) -> CGSize {
    let ideal = subview.sizeThatFits(.unspecified)

    guard let maxWidth, maxWidth.isFinite, ideal.width > maxWidth else {
      return ideal
    }

    return subview.sizeThatFits(
      ProposedViewSize(width: maxWidth, height: proposal.height)
    )
  }

  private func rows(
    for subviews: Subviews,
    proposal: ProposedViewSize,
    maxWidth: CGFloat?
  ) -> [Row] {
    guard !subviews.isEmpty else {
      return []
    }

    let itemSpacing = resolvedItemSpacing()

    var rows = [Row]()
    var currentItems = [Row.Item]()
    var currentWidth: CGFloat = 0
    var currentHeight: CGFloat = 0

    for index in subviews.indices {
      let size = measure(subview: subviews[index], proposal: proposal, maxWidth: maxWidth)
      let nextX = currentItems.isEmpty ? 0 : currentWidth + itemSpacing
      let nextWidth = nextX + size.width

      if let maxWidth, maxWidth.isFinite, !currentItems.isEmpty, nextWidth > maxWidth {
        rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
        currentItems = []
        currentWidth = 0
        currentHeight = 0
      }

      let x = currentItems.isEmpty ? 0 : currentWidth + itemSpacing
      currentItems.append(Row.Item(index: index, size: size, x: x))
      currentWidth = x + size.width
      currentHeight = max(currentHeight, size.height)
    }

    if !currentItems.isEmpty {
      rows.append(Row(items: currentItems, width: currentWidth, height: currentHeight))
    }

    return rows
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) -> CGSize {
    let rows = rows(for: subviews, proposal: proposal, maxWidth: proposal.width)

    guard !rows.isEmpty else {
      return .zero
    }

    let rowSpacing = resolvedRowSpacing()
    let width = rows.map(\.width).max() ?? 0
    let height =
      rows.reduce(0) { partialResult, row in
        partialResult + row.height
      } + rowSpacing * CGFloat(max(rows.count - 1, 0))

    return CGSize(width: width, height: height)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache _: inout ()
  ) {
    let rows = rows(
      for: subviews,
      proposal: proposal,
      maxWidth: bounds.width > 0 ? bounds.width : proposal.width
    )

    guard !rows.isEmpty else {
      return
    }

    let rowSpacing = resolvedRowSpacing()
    var y = bounds.minY

    for row in rows {
      for item in row.items {
        let itemY: CGFloat =
          switch verticalAlignment {
          case .top: y
          case .center: y + (row.height - item.size.height) / 2
          case .bottom: y + (row.height - item.size.height)
          }
        subviews[item.index].place(
          at: CGPoint(x: bounds.minX + item.x, y: itemY),
          anchor: .topLeading,
          proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
        )
      }

      y += row.height + rowSpacing
    }
  }
}
