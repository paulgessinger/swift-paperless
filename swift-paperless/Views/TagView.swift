//
//  TagView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.02.23.
//

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
    @EnvironmentObject var store: DocumentStore

    var tagIDs: [UInt]
    @State var tags: [Tag] = []

    var body: some View {
        VStack {
            WrappingHStack(id: \.id,
                           alignment: .leading,
                           horizontalSpacing: 5,
                           verticalSpacing: 5) {
                ForEach(tags, id: \.id) { tag in
                    TagView(tag: tag)
                }
            }
//            .frame(width: geo.size.width)
//            .background(Color.red)
        }
        .task {
            if tags.isEmpty {
                tags = await store.getTags(tagIDs)
            }
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
                        TagsView(tagIDs: [1, 2, 66, 71])
                    }.frame(width: geo.size.width * fractions[i])
                }
            }
        }
        .environmentObject(store)
    }
}
