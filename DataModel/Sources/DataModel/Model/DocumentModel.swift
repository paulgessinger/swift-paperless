//
//  DocumentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Common
import Foundation
import MetaCodable

public protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var asn: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
    var storagePath: UInt? { get set }
}

public struct NotesPayload: Decodable, Equatable, Sendable, Hashable {
    public var count: Int = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let notes = try? container.decode([Document.Note].self) {
            count = notes.count
        } else {
            count = try (container.decode([UInt].self)).count
        }
    }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct Document: Identifiable, Equatable, Hashable, Sendable {
    public var id: UInt
    public var title: String

    @CodedAt("archive_serial_number")
    @CodedBy(NullCoder<UInt>())
    public var asn: UInt?

    @CodedBy(NullCoder<UInt>())
    public var documentType: UInt?

    @CodedBy(NullCoder<UInt>())
    public var correspondent: UInt?

    @CodedBy(DateOnlyCoder())
    public var created: Date

    public var tags: [UInt]

    @IgnoreEncoding
    public var added: Date?

    @IgnoreEncoding
    public var modified: Date?

    @CodedBy(NullCoder<UInt>())
    public var storagePath: UInt?

    @Default(Owner.unset)
    public var owner: Owner

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

    @IgnoreEncoding
    public private(set) var notes: NotesPayload = .init()

    // Presense of this depends on the endpoint
    // If we didn't get a value, we likely just modified
    @IgnoreEncoding
    @Default(ifMissing: true)
    public private(set) var userCanChange: Bool

    // Presence of this depends on the endpoint
    @IgnoreEncoding
    public var permissions: Permissions? {
        didSet {
            setPermissions = permissions
        }
    }

    // The API wants this extra key for writing perms
    public var setPermissions: Permissions?
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
