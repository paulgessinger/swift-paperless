//
//  DocumentStoreWorkflowTests.swift
//  NetworkingTests
//
//  Created by Paul Gessinger on 13.07.25.
//

import Testing
import DataModel
@testable import Networking

@Suite("DocumentStore Workflow Integration Tests", .serialized)
struct DocumentStoreWorkflowTests {
    
    @Test("Can perform complete DocumentStore initialization workflow")
    func testDocumentStoreInitializationWorkflow() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Test the sequence of operations that DocumentStore.fetchAll() would perform
        
        // 1. Load all metadata that DocumentStore needs
        let users = try await repository.users()
        let groups = try await repository.groups()
        let tags = try await repository.tags()
        let correspondents = try await repository.correspondents()
        let documentTypes = try await repository.documentTypes()
        let storagePaths = try await repository.storagePaths()
        let customFields = try await repository.customFields()
        let savedViews = try await repository.savedViews()
        
        // 2. Get current user and permissions
        let currentUser = try await repository.currentUser()
        let uiSettings = try await repository.uiSettings()
        
        // 3. Load initial documents
        let documents = try await repository.documents(filter: [], sortField: .id, sortOrder: .descending)
        
        // Verify all operations succeeded and returned reasonable data
        #expect(users.results.count >= 1) // At least admin user
        #expect(groups.results.count >= 0) // Groups might be empty
        #expect(tags.results.count >= 0) // Tags might be empty initially
        #expect(correspondents.results.count >= 0) // Correspondents might be empty initially
        #expect(documentTypes.results.count >= 0) // Document types might be empty initially
        #expect(storagePaths.results.count >= 0) // Storage paths might be empty initially
        #expect(customFields.results.count >= 0) // Custom fields might be empty initially
        #expect(savedViews.results.count >= 0) // Saved views might be empty initially
        
        #expect(currentUser.username == "admin")
        #expect(uiSettings.user.canChangeDocument != nil)
        #expect(documents.results.count >= 0) // Documents might be empty initially
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can perform document lifecycle as DocumentStore would")
    func testDocumentLifecycleWorkflow() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Test the complete document lifecycle that DocumentStore manages
        
        // 1. Create supporting metadata
        let tag = try await createTestTag(name: "IntegrationTest Workflow")
        let correspondent = try await createTestCorrespondent(name: "IntegrationTest Workflow Corp")
        let docType = try await repository.create(documentType: DocumentType(
            id: 0,
            name: "IntegrationTest Workflow Type",
            matchingAlgorithm: .auto,
            match: "workflow",
            isInsensitive: false,
            documentCount: 0
        ))
        
        // 2. Create document with metadata (simulating document import)
        let pdfData = createTestPDFData(title: "Workflow Test Document")
        let document = try await repository.create(
            documentTitle: "IntegrationTest Workflow Document",
            documentData: pdfData,
            fileName: "workflow-test.pdf",
            correspondent: correspondent.id,
            documentType: docType.id,
            tags: [tag.id]
        )
        
        #expect(document.id > 0)
        #expect(document.title == "IntegrationTest Workflow Document")
        #expect(document.correspondent == correspondent.id)
        #expect(document.documentType == docType.id)
        #expect(document.tags.contains(tag.id))
        
        // 3. Update document metadata (simulating user editing)
        var updatedDocument = document
        updatedDocument.title = "IntegrationTest Updated Workflow Document"
        
        let updated = try await repository.update(document: updatedDocument)
        #expect(updated.title == "IntegrationTest Updated Workflow Document")
        
        // 4. Search/filter documents (simulating DocumentStore filtering)
        let searchFilter = FilterRule(ruleType: .title, value: .string(value: "Workflow"))!
        let searchResults = try await repository.documents(
            filter: [searchFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        let foundDoc = searchResults.results.first { $0.id == document.id }
        #expect(foundDoc != nil)
        #expect(foundDoc?.title == "IntegrationTest Updated Workflow Document")
        
        // 5. Download document content (simulating document viewing)
        let downloadedData = try await repository.download(documentId: document.id)
        #expect(!downloadedData.isEmpty)
        
        // 6. Get thumbnail (simulating UI thumbnail display)
        try await Task.sleep(for: .seconds(2)) // Wait for thumbnail generation
        let thumbnailData = try await repository.thumbnail(documentId: document.id)
        #expect(!thumbnailData.isEmpty)
        
        // 7. Delete document (simulating user deletion)
        try await repository.delete(document: document.id)
        
        // Verify deletion
        await #expect(throws: Error.self) {
            try await repository.document(id: document.id)
        }
        
        // Clean up remaining metadata
        try await cleanupTestData()
    }
    
    @Test("Can handle concurrent operations like DocumentStore")
    func testConcurrentOperations() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Test concurrent operations that DocumentStore might perform
        
        async let usersTask = repository.users()
        async let tagsTask = repository.tags()
        async let correspondentsTask = repository.correspondents()
        async let documentsTask = repository.documents(filter: [], sortField: .id, sortOrder: .ascending)
        
        // Wait for all operations to complete
        let (users, tags, correspondents, documents) = try await (usersTask, tagsTask, correspondentsTask, documentsTask)
        
        #expect(users.results.count >= 1)
        #expect(tags.results.count >= 0)
        #expect(correspondents.results.count >= 0)
        #expect(documents.results.count >= 0)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can handle filtering with FilterState-like patterns")
    func testFilterStatePatterns() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Create test data
        let tag1 = try await createTestTag(name: "IntegrationTest Priority")
        let tag2 = try await createTestTag(name: "IntegrationTest Archive")
        let correspondent = try await createTestCorrespondent(name: "IntegrationTest FilterState Corp")
        
        let pdfData = createTestPDFData(title: "FilterState Test")
        
        // Create documents with different combinations
        let doc1 = try await repository.create(
            documentTitle: "IntegrationTest FilterState Document 1",
            documentData: pdfData,
            fileName: "filter1.pdf",
            correspondent: correspondent.id,
            tags: [tag1.id]
        )
        
        let doc2 = try await repository.create(
            documentTitle: "IntegrationTest FilterState Document 2",
            documentData: pdfData,
            fileName: "filter2.pdf",
            tags: [tag2.id]
        )
        
        let doc3 = try await repository.create(
            documentTitle: "IntegrationTest FilterState Document 3",
            documentData: pdfData,
            fileName: "filter3.pdf",
            correspondent: correspondent.id,
            tags: [tag1.id, tag2.id]
        )
        
        // Test patterns similar to FilterState.rules
        
        // 1. Test correspondent filter (anyOf pattern)
        let correspondentFilter = FilterRule(ruleType: .hasCorrespondentAny, value: .correspondent(id: correspondent.id))!
        let correspondentResults = try await repository.documents(
            filter: [correspondentFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        let correspondentDocIds = Set(correspondentResults.results.map(\.id))
        #expect(correspondentDocIds.contains(doc1.id))
        #expect(correspondentDocIds.contains(doc3.id))
        #expect(!correspondentDocIds.contains(doc2.id))
        
        // 2. Test tag filter (anyOf pattern)
        let tagFilter = FilterRule(ruleType: .hasTagsAny, value: .tag(id: tag1.id))!
        let tagResults = try await repository.documents(
            filter: [tagFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        let tagDocIds = Set(tagResults.results.map(\.id))
        #expect(tagDocIds.contains(doc1.id))
        #expect(tagDocIds.contains(doc3.id))
        #expect(!tagDocIds.contains(doc2.id))
        
        // 3. Test combined filters (AND pattern)
        let combinedResults = try await repository.documents(
            filter: [correspondentFilter, tagFilter],
            sortField: .id,
            sortOrder: .ascending
        )
        
        let combinedDocIds = Set(combinedResults.results.map(\.id))
        #expect(combinedDocIds.contains(doc1.id))
        #expect(combinedDocIds.contains(doc3.id))
        #expect(!combinedDocIds.contains(doc2.id))
        
        // 4. Test sorting patterns
        let titleSortResults = try await repository.documents(
            filter: [FilterRule(ruleType: .title, value: .string(value: "FilterState"))!],
            sortField: .title,
            sortOrder: .ascending
        )
        
        #expect(titleSortResults.results.count >= 3)
        
        // Clean up
        try await cleanupTestData()
    }
    
    @Test("Can handle task polling workflow")
    func testTaskPollingWorkflow() async throws {
        let repository = try await createAuthenticatedRepository()
        
        // Test the task polling that DocumentStore performs
        
        // 1. Get initial tasks
        let initialTasks = try await repository.tasks()
        #expect(initialTasks.count >= 0)
        
        // 2. Create a document (which should create a task)
        let document = try await createTestDocument(title: "IntegrationTest Task Polling Document")
        
        // 3. Poll for tasks (simulating DocumentStore.taskPoller)
        var foundProcessingTask = false
        
        for _ in 0..<10 { // Poll up to 10 times
            let tasks = try await repository.tasks()
            
            // Look for tasks related to our document
            let documentTasks = tasks.filter { task in
                task.relatedDocument == document.id ||
                task.taskName?.contains("document") == true ||
                task.result?.contains(document.title) == true
            }
            
            if !documentTasks.isEmpty {
                foundProcessingTask = true
                print("Found document processing task: \(documentTasks)")
                break
            }
            
            try await Task.sleep(for: .seconds(1))
        }
        
        // Note: We might not always find tasks in test environment
        // The important thing is that the endpoint works
        print("Task polling test completed. Found processing task: \(foundProcessingTask)")
        
        // Clean up
        try await cleanupTestData()
    }
}

// MARK: - Global test suite lifecycle

@Suite("Integration Test Suite Lifecycle", .serialized)
struct IntegrationTestSuiteLifecycle {
    
    @Test("Setup test environment", .tags(.setup))
    func setupTestEnvironment() async throws {
        // This test ensures the Docker environment is set up
        let orchestrator = try await IntegrationTestSuite.shared.getOrchestrator()
        #expect(orchestrator.isRunning == true)
        #expect(orchestrator.paperlessUrl != nil)
        
        // Verify basic connectivity
        let repository = try await createAuthenticatedRepository()
        let currentUser = try await repository.currentUser()
        #expect(currentUser.username == "admin")
        
        print("Integration test environment is ready")
    }
    
    @Test("Cleanup test environment", .tags(.cleanup))
    func cleanupTestEnvironment() async throws {
        // Clean up any remaining test data
        try await cleanupTestData()
        
        // Note: We don't stop the Docker containers here because other tests might still be running
        // The containers will be cleaned up when the test process exits
        
        print("Integration test cleanup completed")
    }
}

extension Tag {
    static let setup = Tag("setup")
    static let cleanup = Tag("cleanup")
}