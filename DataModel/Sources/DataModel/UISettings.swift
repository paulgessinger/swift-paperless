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
public struct UISettingsSettings: Sendable {
    @Default(UISettingsDocumentEditing.default)
    public var documentEditing: UISettingsDocumentEditing

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
