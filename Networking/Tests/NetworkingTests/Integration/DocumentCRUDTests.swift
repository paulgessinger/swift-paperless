//
//  DocumentCRUDTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
@testable import Networking

@Suite("Document CRUD Integration Tests", .serialized)
struct DocumentCRUDTests {
    
    @Test("Can create a document")
    func testCreateDocument() async throws {
        let document = try await createTestDocument(title: "Test Document Creation")
        
        #expect(document.id > 0)
        #expect(document.title == "Test Document Creation")
        #expect(document.originalFileName == "Test Document Creation.pdf")
        #expect(document.mimeType == "application/pdf")
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can retrieve a document by ID")
    func testRetrieveDocument() async throws {
        let originalDocument = try await createTestDocument(title: "Test Document Retrieval")
        let repository = try await createAuthenticatedRepository()
        
        let retrievedDocument = try await repository.document(id: originalDocument.id)
        
        #expect(retrievedDocument.id == originalDocument.id)
        #expect(retrievedDocument.title == originalDocument.title)
        #expect(retrievedDocument.originalFileName == originalDocument.originalFileName)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can update document metadata")
    func testUpdateDocumentMetadata() async throws {
        let document = try await createTestDocument(title: "Test Document Update")
        let repository = try await createAuthenticatedRepository()
        
        // Update the document
        var updatedDocument = document
        updatedDocument.title = "Updated Test Document"
        
        let result = try await repository.update(document: updatedDocument)
        
        #expect(result.id == document.id)
        #expect(result.title == "Updated Test Document")
        
        // Verify the update persisted
        let retrievedDocument = try await repository.document(id: document.id)
        #expect(retrievedDocument.title == "Updated Test Document")
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can delete a document")
    func testDeleteDocument() async throws {
        let document = try await createTestDocument(title: "Test Document Deletion")
        let repository = try await createAuthenticatedRepository()
        
        // Delete the document
        try await repository.delete(document: document.id)
        
        // Verify it's deleted by trying to retrieve it
        await #expect(throws: Error.self) {
            try await repository.document(id: document.id)
        }
        
        // Clean up (shouldn't be needed, but just in case)
        try await cleanupTestData()
    }
    
    @Test("Can list documents with pagination")
    func testListDocumentsWithPagination() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create multiple test documents
        let document1 = try await createTestDocument(title: "IntegrationTest Document 1")
        let document2 = try await createTestDocument(title: "IntegrationTest Document 2")
        let document3 = try await createTestDocument(title: "IntegrationTest Document 3")
        
        // Get documents with pagination
        let response = try await repository.documents(
            filter: [],
            sortField: .id,
            sortOrder: .ascending,
            page: 1,
            pageSize: 2
        )
        
        #expect(response.results.count <= 2) // Should respect page size
        #expect(response.count >= 3) // Should have at least our 3 test documents
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can download document content")
    func testDownloadDocumentContent() async throws {
        let document = try await createTestDocument(title: "Test Document Download")
        let repository = try await createAuthenticatedRepository()
        
        let downloadedData = try await repository.download(documentId: document.id)
        
        #expect(!downloadedData.isEmpty)
        // Should be PDF data
        let pdfHeader = "%PDF-".data(using: .utf8)!
        #expect(downloadedData.starts(with: pdfHeader))
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can get document thumbnail")
    func testGetDocumentThumbnail() async throws {
        let document = try await createTestDocument(title: "Test Document Thumbnail")
        let repository = try await createAuthenticatedRepository()
        
        // Wait a moment for thumbnail generation
        try await Task.sleep(for: .seconds(2))
        
        let thumbnailData = try await repository.thumbnail(documentId: document.id)
        
        #expect(!thumbnailData.isEmpty)
        // Should be image data (WebP or JPEG)
        let isWebP = thumbnailData.starts(with: "RIFF".data(using: .utf8)!)
        let isJPEG = thumbnailData.count >= 2 && thumbnailData[0] == 0xFF && thumbnailData[1] == 0xD8
        #expect(isWebP || isJPEG)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can search documents by title")
    func testSearchDocumentsByTitle() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test documents with specific titles
        let document1 = try await createTestDocument(title: "IntegrationTest Searchable Document Alpha")
        let document2 = try await createTestDocument(title: "IntegrationTest Searchable Document Beta")
        let document3 = try await createTestDocument(title: "IntegrationTest Other Document")
        
        // Search for documents containing "Searchable"
        let searchRule = FilterRule(ruleType: .title, value: .string(value: "Searchable"))!
        let response = try await repository.documents(
            filter: [searchRule],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 2)
        let titles = response.results.map(\.title)
        #expect(titles.contains("IntegrationTest Searchable Document Alpha"))
        #expect(titles.contains("IntegrationTest Searchable Document Beta"))
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can handle document creation with tags")
    func testCreateDocumentWithTags() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create a test tag first
        let tag = try await createTestTag(name: "IntegrationTest Important")
        
        // Create document with tag
        let pdfData = createTestPDFData(title: "Tagged Document")
        let document = try await repository.create(
            documentTitle: "IntegrationTest Tagged Document",
            documentData: pdfData,
            fileName: "tagged-document.pdf",
            tags: [tag.id]
        )
        
        #expect(document.tags.contains(tag.id))
        
        // Verify by retrieving the document
        let retrievedDocument = try await repository.document(id: document.id)
        #expect(retrievedDocument.tags.contains(tag.id))
        
        // Clean up
        try await cleanupTestData()
    }
}