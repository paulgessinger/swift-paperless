//
//  TagView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.02.23.
//

import Flow
import SwiftUI
import WrappingStack

struct TagView: View {
    @EnvironmentObject var store: DocumentStore

    @State var tag: Tag?

    var tagID: UInt?

    init(tagID: UInt) {
        self.tagID = tagID
    }

    init(tag: Tag) {
        self._tag = State(initialValue: tag)
    }

    var body: some View {
        Group {
            if let tag = tag {
                Text("\(tag.name)")
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.body)
                    .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .background(tag.color)
                    .foregroundColor(tag.textColor)
                    .clipShape(Capsule())
            }
            else {
                ProgressView()
            }
        }
        .task {
            if let tagID = tagID {
                tag = await store.getTag(id: tagID)
            }
        }
    }
}

struct TagsView: View {
    var tags: [Tag]

    var action: ((Tag) -> ())?

    init(tags: [Tag], action: ((Tag) -> ())? = nil) {
        self.tags = tags
        self.action = action
    }

    var body: some View {
        HStack {
            HFlow {
                ForEach(tags, id: \.id) { tag in
                    let v = TagView(tag: tag)

                    if let action = action {
                        v.onTapGesture {
                            action(tag)
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

    static let fractions = [1.0, 0.8, 0.6, 0.4, 0.2]

    static let store = DocumentStore()

    static var previews: some View {
        VStack {
            Spacer()
            ForEach(0 ..< fractions.count, id: \.self) { i in
                GeometryReader { geo in
                    ZStack {
                        Rectangle().fill(.blue)
                        TagsView(tags: tags)
                    }.frame(width: geo.size.width * fractions[i])
                }
            }
        }
        .environmentObject(store)
    }
}
