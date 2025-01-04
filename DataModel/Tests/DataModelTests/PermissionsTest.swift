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
    @Test func testDecoding() async throws {
        let data = testData("Data/permissions.json")!

        struct Response: Decodable {
            var permissions: UserPermissions
        }

        let permissions = try decoder.decode(Response.self, from: data).permissions

        // Document related permissions
        #expect(permissions.test(.add, for: .document))
        #expect(permissions.test(.view, for: .document))
        #expect(permissions.test(.change, for: .document))
        #expect(permissions.test(.delete, for: .document))

        // Document Type permissions
        #expect(permissions.test(.add, for: .documentType))
        #expect(permissions.test(.view, for: .documentType))
        #expect(permissions.test(.change, for: .documentType))
        #expect(permissions.test(.delete, for: .documentType))

        // Storage Path permissions
        #expect(permissions.test(.view, for: .storagePath))
        #expect(permissions.test(.change, for: .storagePath))
        #expect(permissions.test(.delete, for: .storagePath))
        #expect(permissions.test(.add, for: .storagePath))

        // User management permissions
        #expect(permissions.test(.add, for: .user))
        #expect(permissions.test(.view, for: .user))
        #expect(permissions.test(.change, for: .user))
        #expect(permissions.test(.delete, for: .user))

        // Mail related permissions
        #expect(permissions.test(.view, for: .mailAccount))
        #expect(permissions.test(.add, for: .mailAccount))
        #expect(permissions.test(.change, for: .mailAccount))
        #expect(permissions.test(.delete, for: .mailAccount))

        #expect(permissions.test(.view, for: .mailRule))
        #expect(permissions.test(.add, for: .mailRule))
        #expect(permissions.test(.change, for: .mailRule))
        #expect(permissions.test(.delete, for: .mailRule))

        // Workflow permissions
        #expect(permissions.test(.view, for: .workflow))
        #expect(permissions.test(.add, for: .workflow))
        #expect(permissions.test(.change, for: .workflow))
        #expect(permissions.test(.delete, for: .workflow))

        // Custom field permissions
        #expect(permissions.test(.view, for: .customField))
        #expect(permissions.test(.add, for: .customField))
        #expect(permissions.test(.change, for: .customField))
        #expect(permissions.test(.delete, for: .customField))

        // Tag permissions
        #expect(permissions.test(.view, for: .tag))
        #expect(permissions.test(.add, for: .tag))
        #expect(permissions.test(.change, for: .tag))
        #expect(permissions.test(.delete, for: .tag))

        // Note permissions
        #expect(permissions.test(.view, for: .note))
        #expect(permissions.test(.add, for: .note))
        #expect(permissions.test(.change, for: .note))
        #expect(permissions.test(.delete, for: .note))

        // Correspondent permissions
        #expect(permissions.test(.view, for: .correspondent))
        #expect(permissions.test(.add, for: .correspondent))
        #expect(permissions.test(.change, for: .correspondent))
        #expect(permissions.test(.delete, for: .correspondent))

        // UI Settings permissions
        #expect(permissions.test(.view, for: .uiSettings))
        #expect(permissions.test(.add, for: .uiSettings))
        #expect(permissions.test(.change, for: .uiSettings))
        #expect(permissions.test(.delete, for: .uiSettings))

        // Saved view permissions
        #expect(permissions.test(.view, for: .savedView))
        #expect(permissions.test(.add, for: .savedView))
        #expect(permissions.test(.change, for: .savedView))
        #expect(permissions.test(.delete, for: .savedView))
    }

    @Test func testEncoding() async throws {
        var permissions = UserPermissions(rules: [:])
        permissions.set(.add, to: true, for: .document)
        permissions.set(.view, to: true, for: .document)
        permissions.set(.change, to: true, for: .user)

        let encodedData = try JSONEncoder().encode(permissions)

        let expectedOutputSet: Set<String> = ["add_document", "view_document", "change_user"]
        let decodedArray = try JSONDecoder().decode([String].self, from: encodedData)
        let encodedStringSet = Set(decodedArray)
        #expect(encodedStringSet == expectedOutputSet)
    }

    @Test func testPermissionSetDescription() {
        var permissionSet = UserPermissions.PermissionSet()

        // Empty permission set
        #expect(permissionSet.description == "----")

        // Single permission
        permissionSet.set(.view)
        #expect(permissionSet.description == "v---")

        // Multiple permissions
        permissionSet.set(.add)
        #expect(permissionSet.description == "va--")

        // All permissions
        permissionSet.set(.change)
        permissionSet.set(.delete)
        #expect(permissionSet.description == "vacd")

        permissionSet.set(.add, to: false)
        #expect(permissionSet.description == "v-cd")

        // Reset to empty
        permissionSet = UserPermissions.PermissionSet()
        #expect(permissionSet.description == "----")
    }

    @Test func testUserPermissionsDescription() {
        var permissions = UserPermissions(rules: [:])

        // Empty permissions
        let emptyDescription = permissions.matrix
        #expect(emptyDescription.contains("vacd"))
        #expect(emptyDescription.matches(of: /document\\s+----/) != nil)
        #expect(emptyDescription.matches(of: /tag\\s+----/) != nil)

        // Add some permissions
        permissions.set(.view, to: true, for: .document)
        permissions.set(.add, to: true, for: .document)
        permissions.set(.change, to: true, for: .tag)
        permissions.set(.delete, to: true, for: .user)

        let description = permissions.matrix
        #expect(description.matches(of: /document\\s+va--/) != nil)
        #expect(description.matches(of: /tag\\s+--c-/) != nil)
        #expect(description.matches(of: /user\\s+---d/) != nil)

        // Verify format
        let lines = description.split(separator: "\n")
        #expect(lines.count == UserPermissions.Resource.allCases.count + 1) // +1 for header
        #expect(lines[0].hasSuffix("vacd"))

        // Verify consistent padding
        let contentLines = lines.dropFirst()
        print(description)
        let maxWidth = UserPermissions.Resource.allCases
            .map(\.rawValue.count)
            .max() ?? 0
        for line in contentLines {
            #expect(line.count == maxWidth + 5)
        }
    }

    @Test func testFullAccess() {
        let permissions = UserPermissions.full

        // Test that all resources have all permissions
        for resource in UserPermissions.Resource.allCases {
            for operation in UserPermissions.Operation.allCases {
                #expect(permissions.test(operation, for: resource),
                        "Expected \(resource) to have \(operation) permission")
            }
        }

        // Verify the matrix shows full access
        let matrix = permissions.matrix
        for line in matrix.split(separator: "\n").dropFirst() {
            #expect(line.hasSuffix("vacd"),
                    "Expected line to end with 'vacd': \(line)")
        }
    }
}
