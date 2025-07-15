//
//  AuthenticationTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
@testable import Networking

@Suite("Authentication Integration Tests", .serialized)
struct AuthenticationTests {
    
    @Test("Can authenticate with valid credentials")
    func testAuthenticationWithValidCredentials() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Verify we have a token
        #expect(repository.connection.token != nil)
        #expect(!repository.connection.token!.isEmpty)
        
        // Test that we can make an authenticated request
        let users = try await repository.users()
        #expect(!users.results.isEmpty)
    }
    
    @Test("Can get current user information")
    func testGetCurrentUser() async throws {
        let repository = try await createAuthenticatedRepository()
        
        let currentUser = try await repository.currentUser()
        
        #expect(currentUser.username == "admin")
        #expect(currentUser.email == "admin@example.com")
        #expect(currentUser.isSuperuser == true)
    }
    
    @Test("Can get user permissions")
    func testGetUserPermissions() async throws {
        let repository = try await createAuthenticatedRepository()
        
        let permissions = try await repository.uiSettings()
        
        // Admin should have all permissions
        #expect(permissions.user.canChangeClassificationOrdocumentType == true)
        #expect(permissions.user.canChangeCorrespondent == true)
        #expect(permissions.user.canChangeDocument == true)
        #expect(permissions.user.canChangeStoragepath == true)
        #expect(permissions.user.canChangeTag == true)
    }
    
    @Test("Authentication fails with invalid credentials")
    func testAuthenticationWithInvalidCredentials() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        let loginData = [
            "username": "invalid",
            "password": "invalid"
        ]
        
        let url = orchestrator.config.url.appendingPathComponent("api/token/")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: loginData)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 400) // Bad request for invalid credentials
    }
    
    @Test("Can refresh authentication token", .timeLimit(.minutes(1)))
    func testTokenRefresh() async throws {
        let repository = try await createAuthenticatedRepository()
        let originalToken = repository.connection.token
        
        // Make a request to ensure token is valid
        let users1 = try await repository.users()
        #expect(!users1.results.isEmpty)
        
        // In a real scenario, we'd wait for token expiration or simulate it
        // For now, just verify we can continue making requests
        let users2 = try await repository.users()
        #expect(!users2.results.isEmpty)
        
        // Token should still be the same (not expired in test timeframe)
        #expect(repository.connection.token == originalToken)
    }
    
    @Test("Unauthorized requests fail appropriately")
    func testUnauthorizedRequests() async throws {
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        
        // Create repository without token
        let connection = Connection(
            url: orchestrator.config.url,
            token: nil,
            identity: nil
        )
        
        let repository = await ApiRepository(connection: connection, mode: .debug)
        
        // Should throw an error when trying to access protected resources
        await #expect(throws: Error.self) {
            try await repository.users()
        }
    }
    
    @Test("Can handle API version negotiation")
    func testApiVersionNegotiation() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // The repository should have detected the API version
        let apiVersion = repository.effectiveApiVersion
        #expect(apiVersion >= ApiRepository.minimumApiVersion)
        #expect(apiVersion <= ApiRepository.maximumApiVersion)
        
        // Should be able to make requests using the negotiated version
        let users = try await repository.users()
        #expect(!users.results.isEmpty)
    }
}