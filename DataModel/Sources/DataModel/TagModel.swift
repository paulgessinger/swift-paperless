//
//  TagModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Common
import Foundation
import SwiftUI

public protocol TagProtocol:
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

public extension TagProtocol {
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

public struct ProtoTag: Encodable, TagProtocol, MatchingModel {
    public var isInboxTag: Bool
    public var name: String
    public var slug: String
    public var color: HexColor

    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool

    public init(isInboxTag: Bool = false, name: String = "", slug: String = "", color: HexColor = Color.gray.hex, match: String = "", matchingAlgorithm: MatchingAlgorithm = .auto, isInsensitive: Bool = true) {
        self.isInboxTag = isInboxTag
        self.name = name
        self.slug = slug
        self.color = color
        self.match = match
        self.matchingAlgorithm = matchingAlgorithm
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    public static func placeholder(_ length: Int) -> Self {
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

public struct Tag:
    Codable,
    Identifiable,
    Model,
    TagProtocol,
    MatchingModel,
    Equatable,
    Hashable,
    Sendable
{
    public var id: UInt
    public var isInboxTag: Bool
    public var name: String
    public var slug: String
    public var color: HexColor

    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool

    public init(id: UInt, isInboxTag: Bool, name: String, slug: String, color: HexColor, match: String, matchingAlgorithm: MatchingAlgorithm, isInsensitive: Bool) {
        self.id = id
        self.isInboxTag = isInboxTag
        self.name = name
        self.slug = slug
        self.color = color
        self.match = match
        self.matchingAlgorithm = matchingAlgorithm
        self.isInsensitive = isInsensitive
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case isInboxTag = "is_inbox_tag"
        case name, slug, color
        case match
        case matchingAlgorithm = "matching_algorithm"
        case isInsensitive = "is_insensitive"
    }

    public static func placeholder(_ length: Int) -> Self {
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

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
