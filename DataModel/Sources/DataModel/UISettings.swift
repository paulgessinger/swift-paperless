//
//  UISettings.swift
//  DataModel
//
//  Created by Paul Gessinger on 26.12.24.
//

import MetaCodable

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct UISettingsDocumentEditing: Sendable {
    @Default(false)
    public var removeInboxTags: Bool

    @usableFromInline
    static var `default`: Self { .init() }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct UISettingsPermissions: Sendable {
    @Default(nil as UInt?)
    var defaultOwner: UInt?

    @Default([UInt]())
    var defaultViewUsers: [UInt]

    @Default([UInt]())
    var defaultViewGroups: [UInt]

    @Default([UInt]())
    var defaultEditUsers: [UInt]

    @Default([UInt]())
    var defaultEditGroups: [UInt]

    @usableFromInline
    static var `default`: Self { .init() }

    public func applyAsDefaults(to model: inout some PermissionsModel) {
        if case .unset = model.owner {
            model.owner = defaultOwner.map { .user($0) } ?? .none
        }

        var permissions = model.permissions ?? Permissions()
        permissions.view.users = permissions.view.users.isEmpty ? defaultViewUsers : permissions.view.users
        permissions.view.groups = permissions.view.groups.isEmpty ? defaultViewGroups : permissions.view.groups
        permissions.change.users = permissions.change.users.isEmpty ? defaultEditUsers : permissions.change.users
        permissions.change.groups = permissions.change.groups.isEmpty ? defaultEditGroups : permissions.change.groups
        model.permissions = permissions
    }

    public func appliedAsDefaults<T: PermissionsModel>(to model: T) -> T {
        var copy = model
        applyAsDefaults(to: &copy)
        return copy
    }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct UISettingsSettings: Sendable {
    @Default(UISettingsDocumentEditing.default)
    public var documentEditing: UISettingsDocumentEditing

    @Default(UISettingsPermissions.default)
    public var permissions: UISettingsPermissions

    @usableFromInline
    static var `default`: Self { .init() }
}

@Codable
@MemberInit
public struct UISettings: Sendable {
    public var user: User

    @Default(UISettingsSettings.default)
    public var settings: UISettingsSettings

    @IgnoreEncoding
    public var permissions: UserPermissions
}
