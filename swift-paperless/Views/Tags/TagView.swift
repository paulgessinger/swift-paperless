//
//  TagView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.02.23.
//

import DataModel
import Flow
import Networking
import SwiftUI

struct TagView: View {
  @Environment(\.redactionReasons) var redactionReasons

  var inputTag: Tag?

  init(tag: Tag? = nil) {
    inputTag = tag
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
    Group {
      Text(tag.name)
        .lineLimit(1)
        .font(.body)
        .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
        .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .background(tag.color.color)
        .foregroundColor(tag.textColor.color)
        .clipShape(Capsule())
        .italic(inputTag == nil)
        .unredacted()
    }
  }
}

struct TagsView: View {
  var tags: [Tag?]
  var action: ((Tag) -> Void)?

  @Environment(\.redactionReasons) var redactionReasons

  init(tags: [Tag?], action: ((Tag) -> Void)? = nil) {
    self.tags = tags
    self.action = action
  }

  init() {
    tags = []
  }

  var body: some View {
    HStack {
      HFlow {
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
      }
    }
  }
}

struct TagView_Previews: PreviewProvider {
  static let tags: [Tag] = [
    Tag(
      id: 1, isInboxTag: false, name: "Tag",
      slug: "tagname", color: Color.blue.hex,
      match: "", matchingAlgorithm: .auto, isInsensitive: true),

    Tag(
      id: 2, isInboxTag: false, name: "Tag two",
      slug: "tagname", color: Color.red.hex,
      match: "", matchingAlgorithm: .auto, isInsensitive: true),

    Tag(
      id: 3, isInboxTag: false, name: "A very long tag",
      slug: "tagname", color: Color.green.hex,
      match: "", matchingAlgorithm: .auto, isInsensitive: true),

    Tag(
      id: 4, isInboxTag: false, name: "Somewhat shorter",
      slug: "tagname", color: Color.indigo.hex,
      match: "", matchingAlgorithm: .auto, isInsensitive: true),
  ]

  static let fractions = [1.0, 0.8, 0.4, 0.2]

  static let store = DocumentStore(repository: NullRepository())

  static var previews: some View {
    VStack(alignment: .leading) {
      //            ForEach(0 ..< fractions.count, id: \.self) { i in
      //                HStack {
      //                    GeometryReader { geo in
      //                        ZStack {
      //                            Rectangle().fill(.blue)
      //                            TagsView(tags: tags)
      //                        }
      //                        .frame(width: geo.size.width * fractions[i])
      //                    }
      //                }
      //            }
      TagsView()
        .redacted(reason: .placeholder)
    }
    .environmentObject(store)
  }
}
