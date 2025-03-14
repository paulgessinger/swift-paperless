//
//  SortField.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

public enum SortField: RawRepresentable, Codable, Equatable, Hashable, Sendable {
    public typealias RawValue = String

    case asn
    case correspondent
    case title
    case documentType
    case created
    case added
    case modified
    case storagePath
    case owner
    case notes
    case score
    case pageCount
    case other(_: String)

    public static let allCases: [SortField] = [
        .asn,
        .correspondent,
        .title,
        .documentType,
        .created,
        .added,
        .modified,
        .storagePath,
        .owner,
        .notes,
        .pageCount,
        .score,
    ]

    public init?(rawValue: String) {
        switch rawValue {
        case "archive_serial_number": self = .asn
        case "correspondent__name": self = .correspondent
        case "title": self = .title
        case "document_type__name": self = .documentType
        case "created": self = .created
        case "added": self = .added
        case "modified": self = .modified
        case "storage_path__name": self = .storagePath
        case "owner": self = .owner
        case "notes": self = .notes
        case "score": self = .score
        case "page_count": self = .pageCount
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .asn: "archive_serial_number"
        case .correspondent: "correspondent__name"
        case .title: "title"
        case .documentType: "document_type__name"
        case .created: "created"
        case .added: "added"
        case .modified: "modified"
        case .storagePath: "storage_path__name"
        case .owner: "owner"
        case .notes: "notes"
        case .score: "score"
        case .pageCount: "page_count"
        case let .other(value): value
        }
    }
}
