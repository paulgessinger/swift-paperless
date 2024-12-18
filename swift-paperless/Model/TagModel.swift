//
//  TagModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Common
import DataModel
import Foundation
import SwiftUI

protocol TagProtocol:
    Equatable,
    MatchingModel,
    Sendable
{
    var isInboxTag: Bool { get set }
    var name: String { get set }
    var slug: String { get set }
    var color: HexColor { get set }
    var textColor: HexColor { get }

    static func placeholder(_ length: Int) -> Self
}

extension TagProtocol {
    var textColor: HexColor {
        HexColor(color.color.luminance < 0.53 ? .white : .black)
    }
}

private var placeholderColor: Color {
    #if canImport(UIKit)
        Color(uiColor: UIColor.systemGroupedBackground)
    #else
        .gray
    #endif
}

struct ProtoTag: Encodable, TagProtocol, MatchingModel {
    var isInboxTag: Bool = false
    var name: String = ""
    var slug: String = ""
    var color: HexColor = Color.gray.hex

    var match: String = ""
    var matchingAlgorithm: MatchingAlgorithm = .auto
    var isInsensitive: Bool = true

    private enum CodingKeys: String, CodingKey {
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    static func placeholder(_ length: Int) -> Self {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })
        return .init(
            isInboxTag: false,
            name: name,
            slug: "",
            color: placeholderColor.hex
        )
    }
}

struct Tag:
    Codable,
    Identifiable,
    Model,
    TagProtocol,
    MatchingModel,
    Equatable,
    Hashable
{
    var id: UInt
    var isInboxTag: Bool
    var name: String
    var slug: String
    var color: HexColor

    var match: String
    var matchingAlgorithm: MatchingAlgorithm
    var isInsensitive: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    static func placeholder(_ length: Int) -> Self {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })

        return .init(
            id: 0,
            isInboxTag: false,
            name: name,
            slug: "",
            color: placeholderColor.hex,
            match: "",
            matchingAlgorithm: .auto,
            isInsensitive: true
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static var localizedName: String { String(localized: .localizable(.tag)) }
}
