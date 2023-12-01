//
//  PreviewModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

enum PreviewModel {
    static let correspondents: [UInt: Correspondent] = [
        1: Correspondent(id: 1, documentCount: 0, name: "Corr 1", slug: "corr-1", matchingAlgorithm: .auto, match: "", isInsensitive: false),
        2: Correspondent(id: 2, documentCount: 0, name: "Corr 2", slug: "corr-2", matchingAlgorithm: .auto, match: "", isInsensitive: false),
    ]

    static let documentTypes: [UInt: DocumentType] = [
        1: DocumentType(id: 1, name: "Type A", slug: "type-a", match: "", matchingAlgorithm: .none, isInsensitive: false),
        2: DocumentType(id: 2, name: "Type B", slug: "type-b", match: "", matchingAlgorithm: .none, isInsensitive: false),
    ]

    static let tags: [UInt: Tag] = {
        var out: [UInt: Tag] = [:]
        let colors: [Color] = [
            .red,
            .blue,
            .gray,
            .green,
            .yellow,
            .orange,
            .brown,
            .indigo,
            .cyan,
            .mint,
        ]

        for i in 1 ... 20 {
            out[UInt(i)] = Tag(id: UInt(i),
                               isInboxTag: false,
                               name: "Tag \(i)",
                               slug: "tag-\(i)",
                               color: colors[i % colors.count].hex,
                               match: "",
                               matchingAlgorithm: .auto,
                               isInsensitive: true)
        }
        return out
    }()
}
