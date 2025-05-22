//
//  UISettingsTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 26.12.24.
//

@testable import DataModel
import Foundation
import Testing

@Suite
struct UISettingsTest {
    @Test
    func testMinimumVersionDecode() throws {
        let data = try #require(testData("Data/UISettings/ui_settings_min_version.json"))
        let response = try JSONDecoder().decode(UISettings.self, from: data)
        #expect(response.user == User(id: 3, isSuperUser: true, username: "paperless"))
        let settings = response.settings
        #expect(!settings.documentEditing.removeInboxTags)

        // Test permissions
        let permissions = response.permissions
        #expect(permissions.test(.add, for: .tag))
        #expect(permissions.test(.view, for: .document))
        #expect(permissions.test(.change, for: .document))

        // Test some negative cases
        #expect(!permissions.test(.delete, for: .appConfig))
        #expect(!permissions.test(.add, for: .workflow))
    }

    @Test
    func testDecode() throws {
        let data = try #require(testData("Data/UISettings/ui_settings_v2.13.5.json"))
        let response = try JSONDecoder().decode(UISettings.self, from: data)

        #expect(response.user == User(id: 2, isSuperUser: true, username: "paperless"))
        let settings = response.settings
        #expect(settings.documentEditing.removeInboxTags)

        // Test permissions
        let permissions = response.permissions
        #expect(permissions.test(.change, for: .savedView))
        #expect(permissions.test(.delete, for: .user))

        // Test full CRUD permissions for important resources
        let crudResources: [UserPermissions.Resource] = [.document, .tag]
        for resource in crudResources {
            #expect(permissions.test(.view, for: resource))
            #expect(permissions.test(.add, for: resource))
            #expect(permissions.test(.change, for: resource))
            #expect(permissions.test(.delete, for: resource))
        }
    }
}
