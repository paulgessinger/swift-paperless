import DataModel
import Foundation
import Testing

@testable import Networking

@Suite struct EndpointTest {

  // MARK: - Basic Initialization Tests

  @Test func testInitialization() {
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    #expect(endpoint.path == "/api/test")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testInitializationWithQueryItems() {
    let queryItems = [
      URLQueryItem(name: "key1", value: "value1"),
      URLQueryItem(name: "key2", value: "value2"),
    ]
    let endpoint = Endpoint(path: "/api/test", queryItems: queryItems)
    #expect(endpoint.path == "/api/test")
    #expect(endpoint.queryItems.count == 2)
    #expect(endpoint.queryItems[0].name == "key1")
    #expect(endpoint.queryItems[0].value == "value1")
  }

  // MARK: - Static Factory Method Tests

  @Test func testRoot() {
    let endpoint = Endpoint.root()
    #expect(endpoint.path == "/api")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testRemoteVersion() {
    let endpoint = Endpoint.remoteVersion()
    #expect(endpoint.path == "/api/remote_version")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDocumentsWithPageAndRules() {
    let endpoint = Endpoint.documents(page: 2, rules: [], pageSize: 50)
    #expect(endpoint.path == "/api/documents")
    #expect(endpoint.queryItems.count == 3)
    #expect(endpoint.queryItems.contains { $0.name == "page" && $0.value == "2" })
    #expect(endpoint.queryItems.contains { $0.name == "truncate_content" && $0.value == "true" })
    #expect(endpoint.queryItems.contains { $0.name == "page_size" && $0.value == "50" })
  }

  @Test func testDocumentsDefaultPageSize() {
    let endpoint = Endpoint.documents(page: 1, rules: [])
    #expect(endpoint.queryItems.contains { $0.name == "page_size" })
  }

  @Test func testDocument() {
    let endpoint = Endpoint.document(id: 123)
    #expect(endpoint.path == "/api/documents/123")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "full_perms")
    #expect(endpoint.queryItems[0].value == "true")
  }

  @Test func testDocumentWithoutFullPerms() {
    let endpoint = Endpoint.document(id: 456, fullPerms: false)
    #expect(endpoint.path == "/api/documents/456")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testMetadata() {
    let endpoint = Endpoint.metadata(documentId: 789)
    #expect(endpoint.path == "/api/documents/789/metadata")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testNotes() {
    let endpoint = Endpoint.notes(documentId: 100)
    #expect(endpoint.path == "/api/documents/100/notes")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testNote() {
    let endpoint = Endpoint.note(documentId: 200, noteId: 5)
    #expect(endpoint.path == "/api/documents/200/notes")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "id")
    #expect(endpoint.queryItems[0].value == "5")
  }

  @Test func testThumbnail() {
    let endpoint = Endpoint.thumbnail(documentId: 300)
    #expect(endpoint.path == "/api/documents/300/thumb")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDownload() {
    let endpoint = Endpoint.download(documentId: 400)
    #expect(endpoint.path == "/api/documents/400/download")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testSuggestions() {
    let endpoint = Endpoint.suggestions(documentId: 500)
    #expect(endpoint.path == "/api/documents/500/suggestions")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testNextAsn() {
    let endpoint = Endpoint.nextAsn()
    #expect(endpoint.path == "/api/documents/next_asn")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testCorrespondents() {
    let endpoint = Endpoint.correspondents()
    #expect(endpoint.path == "/api/correspondents")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testCreateCorrespondent() {
    let endpoint = Endpoint.createCorrespondent()
    #expect(endpoint.path == "/api/correspondents")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testCorrespondent() {
    let endpoint = Endpoint.correspondent(id: 42)
    #expect(endpoint.path == "/api/correspondents/42")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDocumentTypes() {
    let endpoint = Endpoint.documentTypes()
    #expect(endpoint.path == "/api/document_types")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testCreateDocumentType() {
    let endpoint = Endpoint.createDocumentType()
    #expect(endpoint.path == "/api/document_types")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDocumentType() {
    let endpoint = Endpoint.documentType(id: 7)
    #expect(endpoint.path == "/api/document_types/7")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testTags() {
    let endpoint = Endpoint.tags()
    #expect(endpoint.path == "/api/tags")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testCreateTag() {
    let endpoint = Endpoint.createTag()
    #expect(endpoint.path == "/api/tags")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testTag() {
    let endpoint = Endpoint.tag(id: 99)
    #expect(endpoint.path == "/api/tags/99")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testCreateDocument() {
    let endpoint = Endpoint.createDocument()
    #expect(endpoint.path == "/api/documents/post_document")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDocumentShareLinks() {
    let endpoint = Endpoint.shareLinks(documentId: 123)
    #expect(endpoint.path == "/api/documents/123/share_links")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testDocumentUrl() {
    let endpoint = Endpoint.documentUrl(documentId: 456)
    #expect(endpoint.path == "/api/documents/456")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testSavedViews() {
    let endpoint = Endpoint.savedViews()
    #expect(endpoint.path == "/api/saved_views")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testCreateSavedView() {
    let endpoint = Endpoint.createSavedView()
    #expect(endpoint.path == "/api/saved_views")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testSavedView() {
    let endpoint = Endpoint.savedView(id: 13)
    #expect(endpoint.path == "/api/saved_views/13")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testStoragePaths() {
    let endpoint = Endpoint.storagePaths()
    #expect(endpoint.path == "/api/storage_paths")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testCreateStoragePath() {
    let endpoint = Endpoint.createStoragePath()
    #expect(endpoint.path == "/api/storage_paths")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testStoragePath() {
    let endpoint = Endpoint.storagePath(id: 8)
    #expect(endpoint.path == "/api/storage_paths/8")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testUsers() {
    let endpoint = Endpoint.users()
    #expect(endpoint.path == "/api/users")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testGroups() {
    let endpoint = Endpoint.groups()
    #expect(endpoint.path == "/api/groups")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testUISettings() {
    let endpoint = Endpoint.uiSettings()
    #expect(endpoint.path == "/api/ui_settings")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testTasksDefault() {
    let endpoint = Endpoint.tasks()
    #expect(endpoint.path == "/api/tasks")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems.contains { $0.name == "acknowledged" && $0.value == "false" })
  }

  @Test func testTasksAcknowledged() {
    let endpoint = Endpoint.tasks(acknowledged: true)
    #expect(endpoint.queryItems.contains { $0.name == "acknowledged" && $0.value == "true" })
  }

  @Test func testTask() {
    let endpoint = Endpoint.task(id: 55)
    #expect(endpoint.path == "/api/tasks/55")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testAcknowledgeTasksV1() {
    let endpoint = Endpoint.acknowlegdeTasksV1()
    #expect(endpoint.path == "/api/acknowledge_tasks")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testAcknowledgeTasks() {
    let endpoint = Endpoint.acknowlegdeTasks()
    #expect(endpoint.path == "/api/tasks/acknowledge")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testCustomFields() {
    let endpoint = Endpoint.customFields()
    #expect(endpoint.path == "/api/custom_fields")
    #expect(endpoint.queryItems.count == 1)
    #expect(endpoint.queryItems[0].name == "page_size")
  }

  @Test func testAppConfiguration() {
    let endpoint = Endpoint.appConfiguration()
    #expect(endpoint.path == "/api/config")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testCreateShareLink() {
    let endpoint = Endpoint.createShareLink()
    #expect(endpoint.path == "/api/share_links")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testShareLink() {
    let endpoint = Endpoint.shareLink(id: 42)
    #expect(endpoint.path == "/api/share_links/42")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testTrashActionEndpoint() {
    let endpoint = Endpoint.trash()
    #expect(endpoint.path == "/api/trash")
    #expect(endpoint.queryItems.isEmpty)
  }

  @Test func testTrash() {
    let endpoint = Endpoint.trash(page: 2, pageSize: 25)
    #expect(endpoint.path == "/api/trash")
    #expect(endpoint.queryItems.count == 2)
    #expect(endpoint.queryItems.contains { $0.name == "page" && $0.value == "2" })
    #expect(endpoint.queryItems.contains { $0.name == "page_size" && $0.value == "25" })
  }

  @Test func testTrashDefaultPageSize() {
    let endpoint = Endpoint.trash(page: 1)
    #expect(endpoint.queryItems.contains { $0.name == "page_size" })
  }

  // MARK: - URL Building Tests

  @Test func testURLBuilding() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    let result = try #require(endpoint.url(url: baseURL))

    #expect(result.absoluteString == "https://example.com/api/test/")
  }

  @Test func testURLBuildingWithQueryItems() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let endpoint = Endpoint(
      path: "/api/search",
      queryItems: [
        URLQueryItem(name: "q", value: "test"),
        URLQueryItem(name: "limit", value: "10"),
      ]
    )
    let result = try #require(endpoint.url(url: baseURL))

    #expect(result.absoluteString.contains("https://example.com/api/search"))
    #expect(result.absoluteString.contains("q=test"))
    #expect(result.absoluteString.contains("limit=10"))
  }

  @Test func testURLBuildingWithTrailingSlash() throws {
    let baseURL = try #require(URL(string: "https://example.com/"))
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    let result = try #require(endpoint.url(url: baseURL))

    // Trailing slash should be removed and double slashes normalized
    #expect(result.absoluteString == "https://example.com/api/test/")
  }

  @Test func testURLBuildingWithExistingPath() throws {
    let baseURL = try #require(URL(string: "https://example.com/base/path"))
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    let result = try #require(endpoint.url(url: baseURL))

    #expect(result.absoluteString.contains("/base/path/api/test"))
  }

  @Test func testURLBuildingWithSpecialCharacters() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let endpoint = Endpoint(
      path: "/api/search",
      queryItems: [URLQueryItem(name: "term", value: "hello world")]
    )
    let result = try #require(endpoint.url(url: baseURL))

    // URLQueryItem should handle encoding
    #expect(result.absoluteString.contains("term=hello%20world"))
  }

  @Test func testURLBuildingWithEmptyQueryItems() throws {
    let baseURL = try #require(URL(string: "https://example.com"))
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    let result = try #require(endpoint.url(url: baseURL))

    #expect(!result.absoluteString.contains("?"))
  }

  @Test func testURLBuildingPreservesSchemeAndHost() throws {
    let baseURL = try #require(URL(string: "http://localhost:8000"))
    let endpoint = Endpoint(path: "/api/test", queryItems: [])
    let result = try #require(endpoint.url(url: baseURL))

    #expect(result.scheme == "http")
    #expect(result.host == "localhost")
    #expect(result.port == 8000)
  }
}
