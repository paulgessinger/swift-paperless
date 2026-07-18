//
//  PermissionsTest.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 15.09.2024.
//

import Common
import Foundation
import Testing

@testable import DataModel

struct PermissionsTest {
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
    #expect(emptyDescription.contains("document      ----"))
    #expect(emptyDescription.contains("tag           ----"))

    // Add some permissions
    permissions.set(.view, to: true, for: .document)
    permissions.set(.add, to: true, for: .document)
    permissions.set(.change, to: true, for: .tag)
    permissions.set(.delete, to: true, for: .user)

    let description = permissions.matrix
    #expect(description.contains("document      va--"))
    #expect(description.contains("tag           --c-"))
    #expect(description.contains("user          ---d"))

    // Verify format
    let lines = description.split(separator: "\n")
    #expect(lines.count == UserPermissions.Resource.allCases.count + 1)  // +1 for header
    #expect(lines[0].hasSuffix("vacd"))

    // Verify consistent padding
    let contentLines = lines.dropFirst()
    let maxWidth =
      UserPermissions.Resource.allCases
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
        #expect(
          permissions.test(operation, for: resource),
          "Expected \(resource) to have \(operation) permission")
      }
    }

    // Verify the matrix shows full access
    let matrix = permissions.matrix
    for line in matrix.split(separator: "\n").dropFirst() {
      #expect(
        line.hasSuffix("vacd"),
        "Expected line to end with 'vacd': \(line)")
    }
  }

  @Test func testSubscriptOperator() {
    var permissions = UserPermissions(rules: [:])

    // Test empty permissions
    #expect(permissions[.document].description == "----")
    #expect(permissions[.tag].description == "----")
    #expect(!permissions[.document].test(.view))
    #expect(!permissions[.document].test(.add))

    // Test setting and reading permissions
    permissions.set(.view, to: true, for: .document)
    permissions.set(.add, to: true, for: .document)
    #expect(permissions[.document].description == "va--")
    #expect(permissions[.document].test(.view))
    #expect(permissions[.document].test(.add))
    #expect(!permissions[.document].test(.change))
    #expect(!permissions[.document].test(.delete))

    permissions.set(.change, to: true, for: .tag)
    #expect(permissions[.tag].description == "--c-")
    #expect(!permissions[.tag].test(.view))
    #expect(!permissions[.tag].test(.add))
    #expect(permissions[.tag].test(.change))
    #expect(!permissions[.tag].test(.delete))

    // Test full permissions
    let fullPerms = UserPermissions.full
    #expect(fullPerms[.document].description == "vacd")
    #expect(fullPerms[.user].description == "vacd")
    #expect(fullPerms[.tag].description == "vacd")
    #expect(fullPerms[.document].test(.view))
    #expect(fullPerms[.document].test(.add))
    #expect(fullPerms[.document].test(.change))
    #expect(fullPerms[.document].test(.delete))
  }
}
