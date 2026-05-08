//
//  TagView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.02.23.
//

import Common
import DataModel
import Networking
import SwiftUI

private func blend(_ a: Color, _ b: Color, by t: Double) -> Color {
  var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
  var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
  #if canImport(UIKit)
    UIColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    UIColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
  #elseif canImport(AppKit)
    NSColor(a).getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
    NSColor(b).getRed(&br, green: &bg, blue: &bb, alpha: &ba)
  #endif
  let t = CGFloat(t)
  return Color(
    red: ar + (br - ar) * t,
    green: ag + (bg - ag) * t,
    blue: ab + (bb - ab) * t,
    opacity: aa + (ba - aa) * t
  )
}

struct TagView<Trailing: View>: View {
  @Environment(\.redactionReasons) var redactionReasons
  @Environment(\.colorScheme) private var colorScheme

  var inputTag: Tag?
  var trailing: Trailing

  init(tag: Tag? = nil) where Trailing == EmptyView {
    inputTag = tag
    trailing = EmptyView()
  }

  init(tag: Tag? = nil, @ViewBuilder trailing: () -> Trailing) {
    inputTag = tag
    self.trailing = trailing()
  }

  private var tag: Tag {
    if let inputTag {
      return inputTag
    } else if redactionReasons.contains(.placeholder) {
      return Tag.placeholder(8)
    } else {
      var placeholder = Tag.placeholder(8)
      placeholder.name = String(localized: .permissions(.private))
      return placeholder
    }
  }

  var body: some View {
    HStack(spacing: 4) {
      Text(tag.name)
        .lineLimit(1)
        .truncationMode(.tail)
        .font(.body)
        .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
      trailing
    }
    .padding(
      EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: Trailing.self == EmptyView.self ? 8 : 6)
    )
    .background(tag.color.color.opacity(0.28))
    .foregroundColor(
      blend(colorScheme == .dark ? .white : .black, tag.color.color, by: 0.35)
    )
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .strokeBorder(tag.color.color, lineWidth: 1)
    }
    .italic(inputTag == nil)
    .unredacted()
  }
}

struct TagsView<Content: View>: View {
  let tags: [Tag?]
  let action: ((Tag) -> Void)?

  let content: () -> Content

  @Environment(\.redactionReasons) var redactionReasons

  init(tags: [Tag?], action: ((Tag) -> Void)?, @ViewBuilder content: @escaping () -> Content) {
    self.tags = tags
    self.action = action
    self.content = content
  }

  var body: some View {
    HStack {
      HFlow(verticalAlignment: .center) {
        if redactionReasons.contains(.placeholder) {
          ForEach([4, 6, 5], id: \.self) { v in
            TagView(tag: Tag.placeholder(v))
          }
        } else {
          ForEach(Array(zip(tags.indices, tags)), id: \.0) { _, tag in
            if let action, let tag {
              TagView(tag: tag)
                .onTapGesture {
                  action(tag)
                }
            } else {
              TagView(tag: tag)
            }
          }
        }

        content()
      }

    }
  }
}

extension TagsView where Content == EmptyView {
  init(tags: [Tag?], action: ((Tag) -> Void)? = nil) {
    self.tags = tags
    self.action = action
    self.content = { EmptyView() }
  }

  init() {
    tags = []
    action = nil
    content = { EmptyView() }
  }
}

private func tag(_ id: UInt, _ name: String, _ color: Color) -> Tag {
  Tag(
    id: id, isInboxTag: false, name: name,
    slug: "tag-\(id)", color: color.hex,
    match: "", matchingAlgorithm: .auto, isInsensitive: true)
}

#Preview("Auto color: grayscale") {
  // Luminance crosses the 0.53 white/black threshold somewhere in this strip;
  // the text color of each capsule should flip from white to black accordingly.
  let steps = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
  ScrollView {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(Array(steps.enumerated()), id: \.offset) { idx, w in
        let color = Color(white: w)
        let lum = String(format: "%.2f", color.luminance)
        TagView(tag: tag(UInt(idx), "white \(String(format: "%.2f", w)) · L=\(lum)", color))
      }
    }
    .padding()
  }
}

#Preview("Auto color: threshold") {
  // Greens around the 0.53 threshold — picked because their luminance changes
  // gradually with brightness. Visualizes the exact white→black flip.
  let samples: [(String, Color)] = [
    ("just below", Color(red: 0.30, green: 0.60, blue: 0.30)),
    ("near", Color(red: 0.35, green: 0.65, blue: 0.35)),
    ("at", Color(red: 0.40, green: 0.70, blue: 0.40)),
    ("just above", Color(red: 0.45, green: 0.75, blue: 0.45)),
    ("above", Color(red: 0.55, green: 0.85, blue: 0.55)),
  ]
  VStack(alignment: .leading, spacing: 8) {
    ForEach(Array(samples.enumerated()), id: \.offset) { idx, s in
      let lum = String(format: "%.3f", s.1.luminance)
      TagView(tag: tag(UInt(idx), "\(s.0) · L=\(lum)", s.1))
    }
  }
  .padding()
}

#Preview("Auto color: hues") {
  // System colors span a wide luminance range — each should pick a readable
  // text color automatically.
  let palette: [(String, Color)] = [
    ("red", .red), ("orange", .orange), ("yellow", .yellow),
    ("green", .green), ("mint", .mint), ("teal", .teal),
    ("cyan", .cyan), ("blue", .blue), ("indigo", .indigo),
    ("purple", .purple), ("pink", .pink), ("brown", .brown),
    ("gray", .gray), ("black", .black), ("white", .white),
  ]
  ScrollView {
    HFlow {
      ForEach(Array(palette.enumerated()), id: \.offset) { idx, p in
        let lum = String(format: "%.2f", p.1.luminance)
        TagView(tag: tag(UInt(idx), "\(p.0) · L=\(lum)", p.1))
      }
    }
    .padding()
  }
}

#Preview("Placeholder") {
  TagsView()
    .redacted(reason: .placeholder)
    .environmentObject(DocumentStore(repository: NullRepository()))
}
