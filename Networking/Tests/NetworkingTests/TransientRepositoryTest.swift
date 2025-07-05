import DataModel
import Foundation
import Testing

@testable import Networking

@Suite struct TransientRepositoryTest {
  @Test func testDocumentCRUD() async throws {
    let repository = TransientRepository()

    // Create
    let protoDoc = ProtoDocument(
      title: "Test Document",
      asn: 1,
      documentType: nil,
      correspondent: nil,
      tags: [],
      created: .now,
      storagePath: nil
    )
    try await repository.create(
      document: protoDoc, file: URL(string: "file:///test.pdf")!, filename: "test.pdf"
    )

    // Read - by ID
    let doc = try await repository.document(id: 1)
    #expect(doc != nil)
    #expect(doc?.title == "Test Document")

    // Read - by ASN
    let docByAsn = try await repository.document(asn: 1)
    #expect(docByAsn != nil)
    #expect(docByAsn?.title == "Test Document")

    // Update
    var updatedDoc = doc!
    updatedDoc.title = "Updated Document"
    let result = try await repository.update(document: updatedDoc)
    #expect(result.title == "Updated Document")

    // Delete
    try await repository.delete(document: updatedDoc)
    let deletedDoc = try await repository.document(id: 1)
    #expect(deletedDoc == nil)
  }

  @Test func testTagCRUD() async throws {
    let repository = TransientRepository()

    // Create
    let protoTag = ProtoTag(
      isInboxTag: false,
      name: "Test Tag",
      slug: "test-tag",
      color: .init(.blue),
      match: "",
      matchingAlgorithm: .auto,
      isInsensitive: true
    )
    let tag = try await repository.create(tag: protoTag)
    #expect(tag.name == "Test Tag")

    // Read
    let fetchedTag = try await repository.tag(id: tag.id)
    #expect(fetchedTag != nil)
    #expect(fetchedTag?.name == "Test Tag")

    // Update
    var updatedTag = tag
    updatedTag.name = "Updated Tag"
    let result = try await repository.update(tag: updatedTag)
    #expect(result.name == "Updated Tag")

    // Delete
    try await repository.delete(tag: updatedTag)
    let deletedTag = try await repository.tag(id: tag.id)
    #expect(deletedTag == nil)
  }

  @Test func testCorrespondentCRUD() async throws {
    let repository = TransientRepository()

    // Create
    let protoCorrespondent = ProtoCorrespondent(
      name: "Test Correspondent",
      matchingAlgorithm: .auto,
      match: "",
      isInsensitive: true
    )
    let correspondent = try await repository.create(correspondent: protoCorrespondent)
    #expect(correspondent.name == "Test Correspondent")

    // Read
    let fetchedCorrespondent = try await repository.correspondent(id: correspondent.id)
    #expect(fetchedCorrespondent != nil)
    #expect(fetchedCorrespondent?.name == "Test Correspondent")

    // Update
    var updatedCorrespondent = correspondent
    updatedCorrespondent.name = "Updated Correspondent"
    let result = try await repository.update(correspondent: updatedCorrespondent)
    #expect(result.name == "Updated Correspondent")

    // Delete
    try await repository.delete(correspondent: updatedCorrespondent)
    let deletedCorrespondent = try await repository.correspondent(id: correspondent.id)
    #expect(deletedCorrespondent == nil)
  }

  @Test func testDocumentTypeCRUD() async throws {
    let repository = TransientRepository()

    // Create
    let protoDocType = ProtoDocumentType(
      name: "Test Document Type",
      match: "",
      matchingAlgorithm: .auto,
      isInsensitive: true
    )
    let docType = try await repository.create(documentType: protoDocType)
    #expect(docType.name == "Test Document Type")

    // Read
    let fetchedDocType = try await repository.documentType(id: docType.id)
    #expect(fetchedDocType != nil)
    #expect(fetchedDocType?.name == "Test Document Type")

    // Update
    var updatedDocType = docType
    updatedDocType.name = "Updated Document Type"
    let result = try await repository.update(documentType: updatedDocType)
    #expect(result.name == "Updated Document Type")

    // Delete
    try await repository.delete(documentType: updatedDocType)
    let deletedDocType = try await repository.documentType(id: docType.id)
    #expect(deletedDocType == nil)
  }

  @Test func testStoragePathCRUD() async throws {
    let repository = TransientRepository()

    // Create
    let protoStoragePath = ProtoStoragePath(
      name: "Test Storage Path",
      path: "/test/path",
      matchingAlgorithm: .auto,
      match: "",
      isInsensitive: true
    )
    let storagePath = try await repository.create(storagePath: protoStoragePath)
    #expect(storagePath.name == "Test Storage Path")

    // Read - through list since there's no direct get method
    let paths = try await repository.storagePaths()
    #expect(paths.first?.name == "Test Storage Path")

    // Update
    var updatedPath = storagePath
    updatedPath.name = "Updated Storage Path"
    let result = try await repository.update(storagePath: updatedPath)
    #expect(result.name == "Updated Storage Path")

    // Delete
    try await repository.delete(storagePath: updatedPath)
    let pathsAfterDelete = try await repository.storagePaths()
    #expect(pathsAfterDelete.isEmpty)
  }

  @Test func testDocumentNotes() async throws {
    let repository = TransientRepository()

    // Create a document first
    let protoDoc = ProtoDocument(title: "Test Document")
    try await repository.create(
      document: protoDoc, file: URL(string: "file:///test.pdf")!, filename: "test.pdf"
    )

    // Add a note
    let note = ProtoDocument.Note(note: "Test Note")
    let notes = try await repository.createNote(documentId: 1, note: note)
    #expect(notes.count == 1)
    #expect(notes.first?.note == "Test Note")

    // Get notes
    let notes2 = try await repository.notes(documentId: 1)
    #expect(notes2.count == 1)
    #expect(notes2.first?.note == "Test Note")
    #expect(notes2.first?.id == 1)

    // Delete the note
    let notesAfterDelete = try await repository.deleteNote(id: notes[0].id, documentId: 1)
    #expect(notesAfterDelete.isEmpty)
  }

  @Test func testIdGeneration() async throws {
    let repository = TransientRepository()

    // Create multiple items and verify IDs are unique and sequential
    let tag1 = try await repository.create(tag: ProtoTag(name: "Tag 1"))
    let tag2 = try await repository.create(tag: ProtoTag(name: "Tag 2"))
    let tag3 = try await repository.create(tag: ProtoTag(name: "Tag 3"))

    #expect(tag1.id == 1)
    #expect(tag2.id == 2)
    #expect(tag3.id == 3)
  }

  @Test func testDocumentNotFoundError() async throws {
    let repository = TransientRepository()

    // Try to access a non-existent document's notes
    await #expect(throws: RepositoryError.documentNotFound) {
      _ = try await repository.createNote(
        documentId: 999, note: ProtoDocument.Note(note: "Test")
      )
    }
  }

  @Test func testUserManagement() async throws {
    let repository = TransientRepository()

    // Initially no user is logged in
    await #expect(throws: RepositoryError.noUserLoggedIn) {
      _ = try await repository.currentUser()
    }

    // Add some users
    let user1 = User(id: 1, isSuperUser: true, username: "admin")
    let user2 = User(id: 2, isSuperUser: false, username: "user")
    await repository.addUser(user1)
    await repository.addUser(user2)

    // Test login by ID
    try await repository.login(userId: 1)
    let currentUser = try await repository.currentUser()
    #expect(currentUser.id == 1)
    #expect(currentUser.username == "admin")

    // Test logout
    await repository.logout()
    await #expect(throws: RepositoryError.noUserLoggedIn) {
      _ = try await repository.currentUser()
    }

    // Test login by username
    try await repository.login(username: "user")
    let newCurrentUser = try await repository.currentUser()
    #expect(newCurrentUser.id == 2)
    #expect(newCurrentUser.username == "user")

    // Test login with non-existent user
    await #expect(throws: RepositoryError.userNotFound) {
      try await repository.login(userId: 999)
    }

    await #expect(throws: RepositoryError.userNotFound) {
      try await repository.login(username: "nonexistent")
    }
  }

  @Test func testCustomFields() async throws {
    let repository = TransientRepository()

    // Initially should be empty
    let initialFields = try await repository.customFields()
    #expect(initialFields.isEmpty)

    // Add some custom fields
    _ = try await repository.add(
      customField: CustomField(
        id: 1,
        name: "Invoice Number",
        dataType: .string,
        extraData: .init()
      ))

    _ = try await repository.add(
      customField: CustomField(
        id: 2,
        name: "Amount",
        dataType: .monetary,
        extraData: .init(defaultCurrency: "USD")
      ))

    // Read all fields
    let fields = try await repository.customFields()
    #expect(fields.count == 2)

    // Verify field contents
    let sortedFields = fields.sorted(by: { $0.id < $1.id })
    #expect(sortedFields[0].name == "Invoice Number")
    #expect(sortedFields[0].dataType == .string)

    #expect(sortedFields[1].name == "Amount")
    #expect(sortedFields[1].dataType == .monetary)
    #expect(sortedFields[1].extraData.defaultCurrency == "USD")
  }

  @Test func testDocumentSearch() async throws {
    let repository = TransientRepository()

    // Create test documents with different titles
    let documents = [
      ("Invoice #123", "file1.pdf"),
      ("Receipt for groceries", "file2.pdf"),
      ("Tax document 2024", "file3.pdf"),
      ("Invoice #456", "file4.pdf"),
      ("Meeting notes", "file5.pdf"),
    ]

    for (title, filename) in documents {
      let protoDoc = ProtoDocument(
        title: title,
        asn: nil,
        documentType: nil,
        correspondent: nil,
        tags: [],
        created: .now,
        storagePath: nil
      )
      try await repository.create(
        document: protoDoc, file: URL(string: "file:///\(filename)")!, filename: filename
      )
    }

    // Test searching for "Invoice"
    var filter = FilterState.empty
    filter.searchText = "Invoice"

    let invoiceResults = try await repository.documents(filter: filter)
    let invoiceDocs = try await invoiceResults.fetch(limit: 10)
    #expect(invoiceDocs.count == 2)
    #expect(invoiceDocs.map(\.title).sorted() == ["Invoice #123", "Invoice #456"].sorted())

    // Test searching for "Tax"
    filter.searchText = "Tax"
    let taxResults = try await repository.documents(filter: filter)
    let taxDocs = try await taxResults.fetch(limit: 10)
    #expect(taxDocs.count == 1)
    #expect(taxDocs.first?.title == "Tax document 2024")

    // Test searching for non-existent term
    filter.searchText = "Nonexistent"
    let emptyResults = try await repository.documents(filter: filter)
    let emptyDocs = try await emptyResults.fetch(limit: 10)
    #expect(emptyDocs.isEmpty)
  }

  @Test func testDocumentSearchHelper() async throws {
    let repository = TransientRepository()

    // Create test documents
    let documents = [
      ("Project Alpha", "alpha.pdf"),
      ("Project Beta", "beta.pdf"),
      ("Alpha Protocol", "protocol.pdf"),
    ]

    for (title, filename) in documents {
      let protoDoc = ProtoDocument(
        title: title,
        asn: nil,
        documentType: nil,
        correspondent: nil,
        tags: [],
        created: .now,
        storagePath: nil
      )
      try await repository.create(
        document: protoDoc, file: URL(string: "file:///\(filename)")!, filename: filename
      )
    }

    // Test searching for "Alpha"
    let alphaResults = try await repository.documents(containsTitle: "Alpha")
    #expect(alphaResults.count == 2)
    #expect(alphaResults.map(\.title).sorted() == ["Alpha Protocol", "Project Alpha"].sorted())
  }
}
