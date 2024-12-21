//
//  SortField.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.06.2024.
//

import Foundation

public enum SortField: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case asn = "archive_serial_number"
    case correspondent = "correspondent__name"
    case title
    case documentType = "document_type__name"
    case created
    case added
    case modified
    case storagePath = "storage_path__name"
    case owner
    case notes
    case score
}
