//
//  StoragePathModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation
import MetaCodable

public protocol StoragePathProtocol: Codable, MatchingModel {
    var name: String { get set }
    var path: String { get set }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct StoragePath:
    StoragePathProtocol, Model, Identifiable, Hashable, Named, Sendable
{
    public var id: UInt
    public var name: String
    public var path: String
    public var slug: String

    public var matchingAlgorithm: MatchingAlgorithm
    public var match: String
    public var isInsensitive: Bool
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct ProtoStoragePath: StoragePathProtocol, Sendable {
    @Default("")
    public var name: String

    @Default("")
    public var path: String

    @Default(MatchingAlgorithm.none)
    public var matchingAlgorithm: MatchingAlgorithm

    @Default("")
    public var match: String

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

extension ProtoStoragePath: PermissionsModel {}
