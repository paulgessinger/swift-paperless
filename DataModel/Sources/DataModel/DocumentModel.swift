//
//  DocumentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Common
import Foundation

public protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var asn: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
    var storagePath: UInt? { get set }
}

public struct Document: Identifiable, Equatable, Hashable, Sendable {
    public var id: UInt
    public var title: String

    @NullCodable
    public var asn: UInt?

    @NullCodable
    public var documentType: UInt?

    @NullCodable
    public var correspondent: UInt?

    public var created: Date
    public var tags: [UInt]

    @DecodeOnly
    public var added: Date?

    @DecodeOnly
    public var modified: Date?

    @NullCodable
    public var storagePath: UInt?

    @NullCodable
    public var owner: UInt?

    public struct Note: Identifiable, Equatable, Sendable, Codable, Hashable {
        public var id: UInt
        public var note: String
        public var created: Date

        public init(id: UInt, note: String, created: Date) {
            self.id = id
            self.note = note
            self.created = created
        }
    }

    @DecodeOnly
    public var notes: [Note]

    // Presense of this depends on the endpoint
    @DecodeOnly
    var _userCanChange: Bool?

    public var userCanChange: Bool {
        // If we didn't get a value, we likely just modified
        _userCanChange ?? true
    }

    // Presense of this depends on the endpoint
    @DecodeOnly
    public var permissions: Permissions? {
        didSet {
            setPermissions = permissions
        }
    }

    // The API wants this extra key for writing perms
    public var setPermissions: Permissions?

    public init(id: UInt, title: String, asn: UInt? = nil, documentType: UInt? = nil, correspondent: UInt? = nil, created: Date, tags: [UInt], added: Date? = nil, modified: Date? = nil, storagePath: UInt? = nil, owner: UInt? = nil, notes: [Note], userCanChange: Bool = true, permissions: Permissions? = nil, setPermissions: Permissions? = nil) {
        self.id = id
        self.title = title
        self.asn = asn
        self.documentType = documentType
        self.correspondent = correspondent
        self.created = created
        self.tags = tags
        self.added = added
        self.modified = modified
        self.storagePath = storagePath
        self.owner = owner
        self.notes = notes
        _userCanChange = userCanChange
        self.permissions = permissions
        self.setPermissions = setPermissions
    }

    private enum CodingKeys: String, CodingKey {
        case id, title
        case asn = "archive_serial_number"
        case documentType = "document_type"
        case correspondent, created, tags, added
        case storagePath = "storage_path"
        case notes
        case _userCanChange = "user_can_change"
        case owner
        case permissions
        case setPermissions = "set_permissions"
    }
}

extension Document: Model {}
extension Document: DocumentProtocol {}
extension Document: PermissionsModel {}

public struct ProtoDocument: DocumentProtocol, Equatable, Sendable {
    public var title: String
    public var asn: UInt?
    public var documentType: UInt?
    public var correspondent: UInt?
    public var tags: [UInt]
    public var created: Date
    public var storagePath: UInt?

    public init(title: String = "", asn: UInt? = nil, documentType: UInt? = nil, correspondent: UInt? = nil, tags: [UInt] = [], created: Date = .now, storagePath: UInt? = nil) {
        self.title = title
        self.asn = asn
        self.documentType = documentType
        self.correspondent = correspondent
        self.tags = tags
        self.created = created
        self.storagePath = storagePath
    }

    public struct Note: Codable, Sendable {
        public var note: String

        public init(note: String) {
            self.note = note
        }
    }
}
