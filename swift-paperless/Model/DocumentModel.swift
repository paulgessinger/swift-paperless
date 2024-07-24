//
//  DocumentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var asn: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
    var storagePath: UInt? { get set }
}

struct Document: Identifiable, Equatable, Hashable, Model, DocumentProtocol, Sendable {
    var id: UInt
    var title: String

    @NullCodable
    var asn: UInt?

    @NullCodable
    var documentType: UInt?

    @NullCodable
    var correspondent: UInt?

    var created: Date
    var tags: [UInt]

    @DecodeOnly
    var added: Date?

    @DecodeOnly
    var modified: Date?

    @NullCodable
    var storagePath: UInt?

    struct Note: Identifiable, Equatable, Sendable, Codable, Hashable {
        var id: UInt
        var note: String
        var created: Date
        var document: UInt
        var user: UInt
    }

    @DecodeOnly
    var notes: [Note]

    // Presense of this depends on the endpoint
    @DecodeOnly
    var _userCanChange: Bool?

    var userCanChange: Bool {
        // If we didn't get a value, we likely just modified
        _userCanChange ?? true
    }

    private enum CodingKeys: String, CodingKey {
        case id, title
        case asn = "archive_serial_number"
        case documentType = "document_type"
        case correspondent, created, tags, added
        case storagePath = "storage_path"
        case notes
        case _userCanChange = "user_can_change"
    }

    static var localizedName: String { String(localized: .localizable(.document)) }
}

struct ProtoDocument: DocumentProtocol, Equatable {
    var title: String = ""
    var asn: UInt?
    var documentType: UInt? = nil
    var correspondent: UInt? = nil
    var tags: [UInt] = []
    var created: Date = .now
    var storagePath: UInt? = nil
}
