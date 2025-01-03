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
        #expect(response.settings != nil)
        let settings = response.settings
        #expect(!settings.documentEditing.removeInboxTags)
    }

    @Test
    func testDecode() throws {
        let data = try #require(testData("Data/UISettings/ui_settings_v2.13.5.json"))
        let response = try JSONDecoder().decode(UISettings.self, from: data)
        print(response)

        #expect(response.user == User(id: 2, isSuperUser: true, username: "paperless"))

        #expect(response.settings != nil)
        let settings = response.settings

        #expect(settings.documentEditing.removeInboxTags)
    }
}
