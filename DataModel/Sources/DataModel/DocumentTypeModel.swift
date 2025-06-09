//
//  DocumentTypeModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import MetaCodable

public protocol DocumentTypeProtocol: Equatable, MatchingModel {
    var name: String { get set }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct DocumentType:
    Hashable,
    Identifiable,
    Model,
    DocumentTypeProtocol,
    Named,
    Sendable
{
    public var id: UInt
    public var name: String
    public var slug: String

    public var match: String
    public var matchingAlgorithm: MatchingAlgorithm
    public var isInsensitive: Bool
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoDocumentType: Hashable, DocumentTypeProtocol, Sendable {
    @Default("")
    public var name: String

    @Default("")
    public var match: String

    @Default(MatchingAlgorithm.auto)
    public var matchingAlgorithm: MatchingAlgorithm

    @Default(false)
    public var isInsensitive: Bool

    // For PermissionsModel conformance
    @Default(Owner.unset)
    public var owner: Owner

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

extension ProtoDocumentType: PermissionsModel {}
