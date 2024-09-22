//
//  PermissionsTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 15.09.2024.
//

import Common
@testable import DataModel
import Foundation
import Testing

private let decoder = makeDecoder(tz: .current)

struct PermissionsTest {
    private func getTestData() -> Data {
        """
        {
          "permissions": [
            "view_workflowaction",
            "change_contenttype",
            "add_savedviewfilterrule",
            "delete_paperlesstask",
            "view_taskresult",
            "add_contenttype",
            "view_mailaccount",
            "view_uisettings",
            "change_emailconfirmation",
            "add_socialaccount",
            "change_userobjectpermission",
            "delete_note",
            "delete_emailaddress",
            "delete_mailrule",
            "add_documenttype",
            "change_workflowtrigger",
            "change_socialapp",
            "view_groupresult",
            "view_socialaccount",
            "view_savedview",
            "change_taskresult",
            "add_storagepath",
          ]
        }
        """.data(using: .utf8)!
    }

    @Test func testDecoding() async throws {
        let data = getTestData()

        struct Response: Decodable {
            var permissions: UserPermissions
        }

        let permissions = try decoder.decode(Response.self, from: data).permissions

        #expect(permissions.test(.view, for: .uiSettings))

        #expect(!permissions.test(.view, for: .storagePath))
        #expect(!permissions.test(.change, for: .storagePath))
        #expect(!permissions.test(.delete, for: .storagePath))
        #expect(permissions.test(.add, for: .storagePath))
    }
}
