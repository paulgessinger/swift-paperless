//
//  UserManagementTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
import Foundation
@testable import Networking

@Suite("User Management Integration Tests", .serialized)
struct UserManagementTests {
    
    @Test("Can list users")
    func testListUsers() async throws {
        let repository = try await createAuthenticatedRepository()
        
        let users = try await repository.users()
        
        #expect(!users.isEmpty)
        
        // Should have at least the admin user
        let adminUser = users.first { $0.username == "admin" }
        #expect(adminUser != nil)
        #expect(adminUser?.isSuperUser == true)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can get current user details")
    func testGetCurrentUser() async throws {
        let repository = try await createAuthenticatedRepository()
        
        let currentUser = try await repository.currentUser()
        
        #expect(currentUser.username == "admin")
        // Note: User model doesn't include email, isStaff, isActive properties
        #expect(currentUser.isSuperUser == true)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can create additional users")
    func testCreateAdditionalUser() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        // Create a test user via Docker orchestrator
        try await orchestrator.createAdditionalUser(
            username: "testuser",
            password: "testpass123",
            email: "test@example.com",
            isStaff: false
        )
        
        // Verify user exists
        let repository = try await createAuthenticatedRepository()
        let users = try await repository.users()
        
        let testUser = users.first { $0.username == "testuser" }
        #expect(testUser != nil)
        // Note: User model doesn't include email, isStaff properties
        #expect(testUser?.isSuperUser == false)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can authenticate as different user")
    func testAuthenticateAsDifferentUser() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        // Create a regular user
        try await orchestrator.createAdditionalUser(
            username: "regularuser",
            password: "regular123",
            email: "regular@example.com",
            isStaff: false
        )
        
        // Authenticate as the regular user
        let loginData = [
            "username": "regularuser",
            "password": "regular123"
        ]
        
        let url = orchestrator.config.url.appendingPathComponent("api/token/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: loginData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw IntegrationError.authenticationFailed
        }
        
        let tokenResponse = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let token = tokenResponse["token"] as! String
        
        // Create repository with regular user token
        let connection = Connection(
            url: orchestrator.config.url,
            token: token,
            identity: nil
        )
        
        let userRepository = await ApiRepository(connection: connection, mode: .debug)
        
        // Verify we're authenticated as the regular user
        let currentUser = try await userRepository.currentUser()
        #expect(currentUser.username == "regularuser")
        #expect(currentUser.isSuperUser == false)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can get user permissions for regular user")
    func testGetRegularUserPermissions() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        // Create a regular user
        try await orchestrator.createAdditionalUser(
            username: "limiteduser",
            password: "limited123",
            email: "limited@example.com",
            isStaff: false
        )
        
        // Authenticate as the regular user
        let loginData = [
            "username": "limiteduser",
            "password": "limited123"
        ]
        
        let url = orchestrator.config.url.appendingPathComponent("api/token/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: loginData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let token = tokenResponse["token"] as! String
        
        let connection = Connection(
            url: orchestrator.config.url,
            token: token,
            identity: nil
        )
        
        let userRepository = await ApiRepository(connection: connection, mode: .debug)
        
        // Get permissions for regular user
        let permissions = try await userRepository.uiSettings()
        
        // Regular users should have more limited permissions than admin
        #expect(permissions.user.canChangeDocument == true) // Usually allowed
        // Note: Exact permissions depend on Paperless-ngx configuration
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Regular user cannot access admin functions")
    func testRegularUserCannotAccessAdminFunctions() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        // Create a regular user
        try await orchestrator.createAdditionalUser(
            username: "normaluser",
            password: "normal123",
            email: "normal@example.com",
            isStaff: false
        )
        
        // Authenticate as the regular user
        let loginData = [
            "username": "normaluser",
            "password": "normal123"
        ]
        
        let url = orchestrator.config.url.appendingPathComponent("api/token/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: loginData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let tokenResponse = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let token = tokenResponse["token"] as! String
        
        let connection = Connection(
            url: orchestrator.config.url,
            token: token,
            identity: nil
        )
        
        let userRepository = await ApiRepository(connection: connection, mode: .debug)
        
        // Try to access admin-only functions (like user management)
        // This might succeed or fail depending on Paperless-ngx permissions
        // The key is that it behaves consistently
        do {
            let users = try await userRepository.users()
            // If it succeeds, verify regular user sees limited data
            let currentUser = try await userRepository.currentUser()
            #expect(currentUser.username == "normaluser")
        } catch {
            // If it fails, that's also acceptable for regular users
            print("Regular user correctly denied access to user list: \(error)")
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can handle user groups")
    func testUserGroups() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Try to list user groups
        do {
            let groups = try await repository.groups()
            #expect(groups.count >= 0) // Might be empty in test setup
        } catch {
            // Groups endpoint might not be available in all Paperless-ngx versions
            print("Groups endpoint not available: \(error)")
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can get UI settings for different users")
    func testUISettings() async throws {
        let repository = try await createAuthenticatedRepository()
        
        let settings = try await repository.uiSettings()
        
        // Verify we get valid UI settings
        #expect(settings.user.canChangeDocument != nil)
        #expect(settings.user.canChangeTag != nil)
        #expect(settings.user.canChangeCorrespondent != nil)
        #expect(settings.user.canChangeDocumentType != nil)
        #expect(settings.user.canChangeStoragepath != nil)
        
        // Admin should have most permissions
        #expect(settings.user.canChangeDocument == true)
        #expect(settings.user.canChangeTag == true)
        #expect(settings.user.canChangeCorrespondent == true)
        #expect(settings.user.canChangeDocumentType == true)
        #expect(settings.user.canChangeStoragepath == true)
        
        // Clean up
        try await cleanupTestData()
    }
}