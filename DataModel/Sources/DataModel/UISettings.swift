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
public struct UISettingsDocumentEditing {
    @Default(false)
    public var removeInboxTags: Bool

    @usableFromInline
    static var `default`: Self { .init() }
}

@Codable
@CodingKeys(.snake_case)
@MemberInit
public struct UISettingsSettings {
    @Default(UISettingsDocumentEditing.default)
    public var documentEditing: UISettingsDocumentEditing

    @usableFromInline
    static var `default`: Self { .init() }
}

@Codable
public struct UISettings {
    public var user: User

    @Default(UISettingsSettings.default)
    public var settings: UISettingsSettings

    @IgnoreEncoding
    public var permissions: UserPermissions
}
