//
//  IntegrationTestBase.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
import Common
@testable import Networking

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor IntegrationTestSuite {
    static let shared = IntegrationTestSuite()
    private var orchestrator: DockerOrchestrator?
    private var isInitialized = false
    
    func getOrchestrator() async throws -> DockerOrchestrator {
        if !isInitialized {
            print("Initializing Paperless-ngx test instance...")
            let newOrchestrator = try DockerOrchestrator()
            try await newOrchestrator.startPaperlessInstance()
            self.orchestrator = newOrchestrator
            isInitialized = true
            print("Paperless-ngx test instance ready for testing")
        }
        
        guard let orchestrator = orchestrator else {
            throw IntegrationError.orchestratorNotAvailable
        }
        
        return orchestrator
    }
    
    func cleanup() async {
        if let orchestrator = orchestrator {
            print("Cleaning up Paperless-ngx test instance...")
            try? await orchestrator.stopPaperlessInstance()
            self.orchestrator = nil
            isInitialized = false
        }
    }
}

enum IntegrationError: Error, CustomStringConvertible {
    case orchestratorNotAvailable
    case authenticationFailed
    case testDataCreationFailed(String)
    case documentNotFound
    
    var description: String {
        switch self {
        case .orchestratorNotAvailable:
            return "Docker orchestrator not available"
        case .authenticationFailed:
            return "Authentication failed"
        case .testDataCreationFailed(let message):
            return "Test data creation failed: \(message)"
        case .documentNotFound:
            return "Created document not found"
        }
    }
}

// MARK: - Helper functions for integration tests

func createAuthenticatedRepository() async throws -> ApiRepository {
    let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
    
    // Get auth token using the superuser credentials
    let loginData = [
        "username": orchestrator.config.superUserUsername,
        "password": orchestrator.config.superUserPassword
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
    
    let connection = Connection(
        url: orchestrator.config.url,
        token: token,
        identity: nil
    )
    
    return await ApiRepository(connection: connection, mode: .debug)
}

func createTestDocument(title: String = "IntegrationTest Document") async throws -> Document {
    let repository = try await createAuthenticatedRepository()
    
    // Create a simple PDF document
    let pdfData = createTestPDFData(title: title)
    
    // Write PDF data to temporary file
    let tempDir = FileManager.default.temporaryDirectory
    let fileURL = tempDir.appendingPathComponent("\(UUID().uuidString).pdf")
    try pdfData.write(to: fileURL)
    
    // Create ProtoDocument
    let protoDocument = ProtoDocument(
        title: title,
        asn: nil,
        documentType: nil,
        correspondent: nil,
        tags: [],
        created: .now,
        storagePath: nil
    )
    
    // Create the document via API
    try await repository.create(
        document: protoDocument,
        file: fileURL,
        filename: "\(title).pdf"
    )
    
    // Clean up temporary file
    try FileManager.default.removeItem(at: fileURL)
    
    // Find the created document by searching for it
    // We need to wait a moment for the document to be processed
    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
    
    let filter = FilterState()
    let source = try repository.documents(filter: filter)
    let documents = try await source.fetch(limit: 100)
    
    guard let createdDocument = documents.first(where: { $0.title == title }) else {
        throw IntegrationError.documentNotFound
    }
    
    return createdDocument
}

func createTestTag(name: String = "IntegrationTest Tag") async throws -> DataModel.Tag {
    let repository = try await createAuthenticatedRepository()
    
    let protoTag = ProtoTag(
        isInboxTag: false,
        name: name,
        slug: "",
        color: HexColor(Color(hex: "#ff0000")!),
        match: "",
        matchingAlgorithm: .auto,
        isInsensitive: false
    )
    
    return try await repository.create(tag: protoTag)
}

func createTestCorrespondent(name: String = "IntegrationTest Correspondent") async throws -> Correspondent {
    let repository = try await createAuthenticatedRepository()
    
    return try await repository.create(correspondent: Correspondent(
        id: 0, // Will be assigned by server
        name: name,
        matchingAlgorithm: .auto,
        match: "",
        isInsensitive: false,
        documentCount: 0,
        lastCorrespondence: nil
    ))
}

func cleanupTestData() async throws {
    let repository = try await createAuthenticatedRepository()
    
    // Clean up any test documents, tags, etc. created during tests
    // This helps ensure test isolation
    
    do {
        // Get all test documents and delete them
        let documents = try await repository.documents(filter: [], sortField: .id, sortOrder: .ascending)
        
        for document in documents.results {
            // Only delete documents that look like test documents
            if document.title.contains("Test") || document.title.hasPrefix("IntegrationTest") {
                try? await repository.delete(document: document.id)
            }
        }
        
        // Clean up test tags
        let tags = try await repository.tags()
        for tag in tags.results {
            if tag.name.contains("Test") || tag.name.hasPrefix("IntegrationTest") {
                try? await repository.delete(tag: tag.id)
            }
        }
        
        // Clean up test correspondents, document types, etc.
        let correspondents = try await repository.correspondents()
        for correspondent in correspondents.results {
            if correspondent.name.contains("Test") || correspondent.name.hasPrefix("IntegrationTest") {
                try? await repository.delete(correspondent: correspondent.id)
            }
        }
        
    } catch {
        print("Warning: Could not clean up test data: \(error)")
    }
}

func createTestPDFData(title: String) -> Data {
    // Create minimal PDF data for testing
    let pdfContent = """
    %PDF-1.4
    1 0 obj
    <<
    /Type /Catalog
    /Pages 2 0 R
    >>
    endobj
    2 0 obj
    <<
    /Type /Pages
    /Kids [3 0 R]
    /Count 1
    >>
    endobj
    3 0 obj
    <<
    /Type /Page
    /Parent 2 0 R
    /MediaBox [0 0 612 792]
    /Contents 4 0 R
    >>
    endobj
    4 0 obj
    <<
    /Length 44
    >>
    stream
    BT
    /F1 12 Tf
    100 700 Td
    (\(title)) Tj
    ET
    endstream
    endobj
    xref
    0 5
    0000000000 65535 f 
    0000000009 00000 n 
    0000000058 00000 n 
    0000000115 00000 n 
    0000000201 00000 n 
    trailer
    <<
    /Size 5
    /Root 1 0 R
    >>
    startxref
    294
    %%EOF
    """
    
    return pdfContent.data(using: .utf8) ?? Data()
}