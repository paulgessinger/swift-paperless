//
//  FilteringTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
@testable import Networking

@Suite("Filtering and Search Integration Tests", .serialized)
struct FilteringTests {
    
    @Test("Can filter documents by title")
    func testFilterByTitle() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test documents
        let doc1 = try await createTestDocument(title: "IntegrationTest Important Document")
        let doc2 = try await createTestDocument(title: "IntegrationTest Regular Document")
        let doc3 = try await createTestDocument(title: "IntegrationTest Archive File")
        
        // Filter by title containing "Important"
        let titleFilter = FilterRule(ruleType: .title, value: .string(value: "Important"))!
        let response = try await repository.documents(
            filter: [titleFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 1)
        let foundDocument = response.results.first { $0.id == doc1.id }
        #expect(foundDocument != nil)
        #expect(foundDocument?.title.contains("Important") == true)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can filter documents by content")
    func testFilterByContent() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create documents with specific content
        let doc1 = try await createTestDocument(title: "IntegrationTest Content Search Alpha")
        let doc2 = try await createTestDocument(title: "IntegrationTest Content Search Beta")
        
        // Filter by content (this tests that the backend can search document text)
        let contentFilter = FilterRule(ruleType: .content, value: .string(value: "Alpha"))!
        let response = try await repository.documents(
            filter: [contentFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        // Should find document with "Alpha" in title (which becomes content)
        let foundDoc = response.results.first { $0.id == doc1.id }
        #expect(foundDoc != nil)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can filter documents by tags")
    func testFilterByTags() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test tags
        let importantTag = try await createTestTag(name: "IntegrationTest Important")
        let archiveTag = try await createTestTag(name: "IntegrationTest Archive")
        
        // Create documents with different tags
        let pdfData = createTestPDFData(title: "Tagged Document")
        
        let doc1 = try await repository.create(
            documentTitle: "IntegrationTest Document 1",
            documentData: pdfData,
            fileName: "doc1.pdf",
            tags: [importantTag.id]
        )
        
        let doc2 = try await repository.create(
            documentTitle: "IntegrationTest Document 2", 
            documentData: pdfData,
            fileName: "doc2.pdf",
            tags: [archiveTag.id]
        )
        
        let doc3 = try await repository.create(
            documentTitle: "IntegrationTest Document 3",
            documentData: pdfData,
            fileName: "doc3.pdf",
            tags: [importantTag.id, archiveTag.id]
        )
        
        // Filter by important tag
        let tagFilter = FilterRule(ruleType: .hasTagsAny, value: .tag(id: importantTag.id))!
        let response = try await repository.documents(
            filter: [tagFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 2) // Should find doc1 and doc3
        let foundIds = Set(response.results.map(\.id))
        #expect(foundIds.contains(doc1.id))
        #expect(foundIds.contains(doc3.id))
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can filter documents by correspondent")
    func testFilterByCorrespondent() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test correspondents
        let corp1 = try await createTestCorrespondent(name: "IntegrationTest Corp A")
        let corp2 = try await createTestCorrespondent(name: "IntegrationTest Corp B")
        
        // Create documents with different correspondents
        let pdfData = createTestPDFData(title: "Correspondent Document")
        
        let doc1 = try await repository.create(
            documentTitle: "IntegrationTest Document from Corp A",
            documentData: pdfData,
            fileName: "doc-corp-a.pdf",
            correspondent: corp1.id
        )
        
        let doc2 = try await repository.create(
            documentTitle: "IntegrationTest Document from Corp B",
            documentData: pdfData,
            fileName: "doc-corp-b.pdf",
            correspondent: corp2.id
        )
        
        // Filter by correspondent
        let correspondentFilter = FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: corp1.id))!
        let response = try await repository.documents(
            filter: [correspondentFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 1)
        let foundDocument = response.results.first { $0.id == doc1.id }
        #expect(foundDocument != nil)
        #expect(foundDocument?.correspondent == corp1.id)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can filter documents by document type")
    func testFilterByDocumentType() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test document types
        let invoiceType = try await repository.create(documentType: DocumentType(
            id: 0,
            name: "IntegrationTest Invoice",
            matchingAlgorithm: .auto,
            match: "invoice",
            isInsensitive: false,
            documentCount: 0
        ))
        
        let letterType = try await repository.create(documentType: DocumentType(
            id: 0,
            name: "IntegrationTest Letter",
            matchingAlgorithm: .auto,
            match: "letter",
            isInsensitive: false,
            documentCount: 0
        ))
        
        // Create documents with different types
        let pdfData = createTestPDFData(title: "Typed Document")
        
        let doc1 = try await repository.create(
            documentTitle: "IntegrationTest Invoice Document",
            documentData: pdfData,
            fileName: "invoice.pdf",
            documentType: invoiceType.id
        )
        
        let doc2 = try await repository.create(
            documentTitle: "IntegrationTest Letter Document",
            documentData: pdfData,
            fileName: "letter.pdf",
            documentType: letterType.id
        )
        
        // Filter by document type
        let typeFilter = FilterRule(ruleType: .hasDocumentTypeAny, value: .documentType(id: invoiceType.id))!
        let response = try await repository.documents(
            filter: [typeFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 1)
        let foundDocument = response.results.first { $0.id == doc1.id }
        #expect(foundDocument != nil)
        #expect(foundDocument?.documentType == invoiceType.id)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can combine multiple filters")
    func testCombineMultipleFilters() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test metadata
        let tag = try await createTestTag(name: "IntegrationTest Combined")
        let correspondent = try await createTestCorrespondent(name: "IntegrationTest Combined Corp")
        
        // Create documents
        let pdfData = createTestPDFData(title: "Combined Filter Test")
        
        let doc1 = try await repository.create(
            documentTitle: "IntegrationTest Important Combined Document",
            documentData: pdfData,
            fileName: "combined.pdf",
            correspondent: correspondent.id,
            tags: [tag.id]
        )
        
        let doc2 = try await repository.create(
            documentTitle: "IntegrationTest Other Document",
            documentData: pdfData,
            fileName: "other.pdf",
            correspondent: correspondent.id
        )
        
        // Combine filters: title contains "Important" AND has specific tag
        let titleFilter = FilterRule(ruleType: .title, value: .string(value: "Important"))!
        let tagFilter = FilterRule(ruleType: .hasTagsAny, value: .tag(id: tag.id))!
        
        let response = try await repository.documents(
            filter: [titleFilter, tagFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 1)
        let foundDocument = response.results.first { $0.id == doc1.id }
        #expect(foundDocument != nil)
        #expect(foundDocument?.title.contains("Important") == true)
        #expect(foundDocument?.tags.contains(tag.id) == true)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can filter documents by date range")
    func testFilterByDateRange() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test document
        let doc = try await createTestDocument(title: "IntegrationTest Date Filter Document")
        
        // Filter by created date (should include recent documents)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let startDateFilter = FilterRule(ruleType: .createdAfter, value: .date(value: yesterday))!
        let endDateFilter = FilterRule(ruleType: .createdBefore, value: .date(value: tomorrow))!
        
        let response = try await repository.documents(
            filter: [startDateFilter, endDateFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        #expect(response.results.count >= 1)
        let foundDocument = response.results.first { $0.id == doc.id }
        #expect(foundDocument != nil)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can sort documents by different fields")
    func testSortDocuments() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create multiple test documents with different titles
        let doc1 = try await createTestDocument(title: "IntegrationTest Alpha Document")
        let doc2 = try await createTestDocument(title: "IntegrationTest Beta Document")  
        let doc3 = try await createTestDocument(title: "IntegrationTest Gamma Document")
        
        // Sort by title ascending
        let ascResponse = try await repository.documents(
            filter: [FilterRule(ruleType: .title, value: .string(value: "IntegrationTest"))!],
            sortField: .title,
            sortOrder: .ascending
        )
        
        #expect(ascResponse.results.count >= 3)
        let ascTitles = ascResponse.results.map(\.title)
        let testTitles = ascTitles.filter { $0.contains("IntegrationTest") }
        #expect(testTitles.count >= 3)
        
        // Sort by title descending
        let descResponse = try await repository.documents(
            filter: [FilterRule(ruleType: .title, value: .string(value: "IntegrationTest"))!],
            sortField: .title,
            sortOrder: .descending
        )
        
        #expect(descResponse.results.count >= 3)
        let descTitles = descResponse.results.map(\.title)
        let testDescTitles = descTitles.filter { $0.contains("IntegrationTest") }
        #expect(testDescTitles.count >= 3)
        
        // Clean up
        try await cleanupTestData()
    }
}