//
//  TagView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.02.23.
//

import Flow
import SwiftUI

struct TagView: View {
    @EnvironmentObject var store: DocumentStore
    @Environment(\.redactionReasons) var redactionReasons

    @State var tag: Tag?

    var tagID: UInt?

    init(tagID: UInt) {
        self.tagID = tagID
    }

    init(tag: Tag? = nil) {
        let dummy = Tag(id: 0, isInboxTag: false, name: "        ", slug: "", color: .gray, textColor: .primary)

        self._tag = State(initialValue: tag ?? dummy)
    }

    var body: some View {
        Group {
            if let tag = tag {
                Text("\(tag.name)")
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.body)
                    .opacity(redactionReasons.contains(.placeholder) ? 0 : 1)
                    .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .background(tag.color)
                    .foregroundColor(tag.textColor)
                    .clipShape(Capsule())
                    .unredacted()
            }
            else {
                ProgressView()
            }
        }
        .task {
            if let tagID = tagID {
                if let (_, tag) = await store.getTag(id: tagID) {
                    self.tag = tag
                }
            }
        }
    }
}

struct TagsView: View {
    var tags: [Tag]
    var action: ((Tag) -> ())?

    @Environment(\.redactionReasons) var redactionReasons

    init(tags: [Tag], action: ((Tag) -> ())? = nil) {
        self.tags = tags
        self.action = action
    }

    init() {
        self.tags = []
    }

    var body: some View {
        HStack {
            HFlow {
                if redactionReasons.contains(.placeholder) {
                    ForEach([4, 6, 5], id: \.self) { v in
                        TagView(tag: .placeholder(v))
                    }
                }
                else {
                    ForEach(tags, id: \.id) { tag in
                        if let action = action {
                            TagView(tag: tag).onTapGesture {
                                action(tag)
                            }
                        }
                        else {
                            TagView(tag: tag)
                        }
                    }
                }
            }
            Spacer()
        }
    }
}

struct TagView_Previews: PreviewProvider {
    static let tags: [Tag] = [
        Tag(id: 1, isInboxTag: false, name: "Tag",
            slug: "tagname", color: Color.blue,
            textColor: Color.white),

        Tag(id: 2, isInboxTag: false, name: "Tag two",
            slug: "tagname", color: Color.red,
            textColor: Color.white),

        Tag(id: 3, isInboxTag: false, name: "A very long tag",
            slug: "tagname", color: Color.green,
            textColor: Color.white),

        Tag(id: 4, isInboxTag: false, name: "Somewhat shorter",
            slug: "tagname", color: Color.indigo,
            textColor: Color.white),
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
