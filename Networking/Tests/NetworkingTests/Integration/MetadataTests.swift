//
//  MetadataTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
import Common
@testable import Networking

@Suite("Metadata Integration Tests", .serialized)
struct MetadataTests {
    
    // MARK: - Tag Tests
    
    @Test("Can create and manage tags")
    func testTagCRUD() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create tag
        let protoTag = ProtoTag(
            isInboxTag: false,
            name: "IntegrationTest Tag",
            slug: "",
            color: HexColor(Color(hex: "#FF5733")!),
            match: "important",
            matchingAlgorithm: .auto,
            isInsensitive: false
        )
        let tag = try await repository.create(tag: protoTag)
        
        #expect(tag.id > 0)
        #expect(tag.name == "IntegrationTest Tag")
        #expect(tag.color == "#FF5733")
        
        // Read tag
        let retrievedTag = try await repository.tag(id: tag.id)
        #expect(retrievedTag.name == tag.name)
        #expect(retrievedTag.color == tag.color)
        
        // Update tag
        var updatedTag = tag
        updatedTag.name = "IntegrationTest Updated Tag"
        updatedTag.color = "#33FF57"
        
        let result = try await repository.update(tag: updatedTag)
        #expect(result.name == "IntegrationTest Updated Tag")
        #expect(result.color == "#33FF57")
        
        // List tags
        let tagsResponse = try await repository.tags()
        let tagNames = tagsResponse.map(\.name)
        #expect(tagNames.contains("IntegrationTest Updated Tag"))
        
        // Delete tag
        try await repository.delete(tag: tag.id)
        
        await #expect(throws: Error.self) {
            try await repository.tag(id: tag.id)
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    // MARK: - Correspondent Tests
    
    @Test("Can create and manage correspondents")
    func testCorrespondentCRUD() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create correspondent
        let correspondent = try await repository.create(correspondent: Correspondent(
            id: 0,
            name: "IntegrationTest Corp",
            matchingAlgorithm: .auto,
            match: "corp@example.com",
            isInsensitive: true,
            documentCount: 0,
            lastCorrespondence: nil
        ))
        
        #expect(correspondent.id > 0)
        #expect(correspondent.name == "IntegrationTest Corp")
        #expect(correspondent.match == "corp@example.com")
        #expect(correspondent.isInsensitive == true)
        
        // Read correspondent
        let retrieved = try await repository.correspondent(id: correspondent.id)
        #expect(retrieved.name == correspondent.name)
        
        // Update correspondent
        var updated = correspondent
        updated.name = "IntegrationTest Corporation"
        updated.match = "corporation@example.com"
        
        let result = try await repository.update(correspondent: updated)
        #expect(result.name == "IntegrationTest Corporation")
        #expect(result.match == "corporation@example.com")
        
        // List correspondents
        let response = try await repository.correspondents()
        let names = response.map(\.name)
        #expect(names.contains("IntegrationTest Corporation"))
        
        // Delete correspondent
        try await repository.delete(correspondent: correspondent.id)
        
        await #expect(throws: Error.self) {
            try await repository.correspondent(id: correspondent.id)
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    // MARK: - Document Type Tests
    
    @Test("Can create and manage document types")
    func testDocumentTypeCRUD() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create document type
        let docType = try await repository.create(documentType: DocumentType(
            id: 0,
            name: "IntegrationTest Invoice",
            matchingAlgorithm: .auto,
            match: "invoice",
            isInsensitive: false,
            documentCount: 0
        ))
        
        #expect(docType.id > 0)
        #expect(docType.name == "IntegrationTest Invoice")
        #expect(docType.match == "invoice")
        
        // Read document type
        let retrieved = try await repository.documentType(id: docType.id)
        #expect(retrieved.name == docType.name)
        
        // Update document type
        var updated = docType
        updated.name = "IntegrationTest Invoice Type"
        updated.match = "invoice|bill"
        
        let result = try await repository.update(documentType: updated)
        #expect(result.name == "IntegrationTest Invoice Type")
        #expect(result.match == "invoice|bill")
        
        // List document types
        let response = try await repository.documentTypes()
        let names = response.map(\.name)
        #expect(names.contains("IntegrationTest Invoice Type"))
        
        // Delete document type
        try await repository.delete(documentType: docType.id)
        
        await #expect(throws: Error.self) {
            try await repository.documentType(id: docType.id)
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    // MARK: - Storage Path Tests
    
    @Test("Can create and manage storage paths")
    func testStoragePathCRUD() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create storage path
        let storagePath = try await repository.create(storagePath: StoragePath(
            id: 0,
            name: "IntegrationTest Archive",
            path: "archive/2025/",
            matchingAlgorithm: .auto,
            match: "archive",
            isInsensitive: false,
            documentCount: 0
        ))
        
        #expect(storagePath.id > 0)
        #expect(storagePath.name == "IntegrationTest Archive")
        #expect(storagePath.path == "archive/2025/")
        
        // Read storage path
        let retrieved = try await repository.storagePath(id: storagePath.id)
        #expect(retrieved.name == storagePath.name)
        #expect(retrieved.path == storagePath.path)
        
        // Update storage path
        var updated = storagePath
        updated.name = "IntegrationTest Archive 2025"
        updated.path = "archive/2025/documents/"
        
        let result = try await repository.update(storagePath: updated)
        #expect(result.name == "IntegrationTest Archive 2025")
        #expect(result.path == "archive/2025/documents/")
        
        // List storage paths
        let response = try await repository.storagePaths()
        let names = response.map(\.name)
        #expect(names.contains("IntegrationTest Archive 2025"))
        
        // Delete storage path
        try await repository.delete(storagePath: storagePath.id)
        
        await #expect(throws: Error.self) {
            try await repository.storagePath(id: storagePath.id)
        }
        
        // Clean up
        try await cleanupTestData()
    }
    
    // MARK: - Custom Fields Tests (if supported)
    
    @Test("Can list custom fields")
    func testListCustomFields() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Just test that we can call the endpoint without error
        // Custom fields might not be configured in test instance
        let customFields = try await repository.customFields()
        
        // Should return a list (might be empty)
        #expect(customFields.count >= 0)
        
        // Clean up
        try await cleanupTestData()
    }
    
    // MARK: - Integration with Documents
    
    @Test("Can create document with full metadata")
    func testCreateDocumentWithFullMetadata() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create supporting metadata
        let tag = try await createTestTag(name: "IntegrationTest Important")
        let correspondent = try await createTestCorrespondent(name: "IntegrationTest Sender")
        let docType = try await repository.create(documentType: DocumentType(
            id: 0,
            name: "IntegrationTest Letter",
            matchingAlgorithm: .auto,
            match: "letter",
            isInsensitive: false,
            documentCount: 0
        ))
        
        // Create document with metadata
        let pdfData = createTestPDFData(title: "Full Metadata Document")
        let document = try await repository.create(
            documentTitle: "IntegrationTest Full Metadata Document",
            documentData: pdfData,
            fileName: "full-metadata.pdf",
            correspondent: correspondent.id,
            documentType: docType.id,
            tags: [tag.id]
        )
        
        #expect(document.correspondent == correspondent.id)
        #expect(document.documentType == docType.id)
        #expect(document.tags.contains(tag.id))
        
        // Verify by retrieving
        let retrieved = try await repository.document(id: document.id)
        #expect(retrieved.correspondent == correspondent.id)
        #expect(retrieved.documentType == docType.id)
        #expect(retrieved.tags.contains(tag.id))
        
        // Clean up
        try await cleanupTestData()
    }
}