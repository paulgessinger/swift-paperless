//
//  TagModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import SwiftUI

protocol TagProtocol:
    Equatable,
    MatchingModel
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
        // https://github.com/paperless-ngx/paperless-ngx/blob/0dcfb97824b6184094290138fe401d8368722483/src/documents/serialisers.py#L317-L328

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(color.color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let luminance = sqrt(0.299 * pow(red, 2) + 0.587 * pow(green, 2) + 0.114 * pow(blue, 2))

        return HexColor(luminance < 0.53 ? .white : .black)
    }
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
            color: Color("ElementBackground").hex
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
            color: Color("ElementBackground").hex,
            match: "",
            matchingAlgorithm: .auto,
            isInsensitive: true
        )
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static var localizedName: String { String(localized: .localizable.tag) }
}
