//
//  ApiRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Common
import DataModel
import Foundation
import Semaphore
import SwiftUI
import os

public struct DecodingErrorWithRootType: Error {
  public let type: any Any.Type
  public let error: DecodingError
}

@MainActor
public class ApiRepository {
  public nonisolated
    let connection: Connection

  public enum Mode: Sendable {
    case release
    case debug
  }

  nonisolated
    let mode: Mode

  private let urlSession: URLSession
  private let urlSessionDelegate: PaperlessURLSessionDelegate
  private let contentStore: ContentStore?

  // Per-key in-flight task map: two concurrent downloads of the same blob
  // share one network request rather than racing into the ContentStore.
  private var inFlightDownloads: [ContentStore.Key: Task<URL, Error>] = [:]

  nonisolated
    private let apiVersion: UInt?
  nonisolated
    public static let minimumApiVersion: UInt = 3
  nonisolated
    public static let minimumVersion = Version(1, 14, 1)
  nonisolated
    public static let maximumApiVersion: UInt = 10
  nonisolated
    public let backendVersion: Version?

  public var effectiveApiVersion: UInt {
    min(Self.maximumApiVersion, apiVersion ?? Self.maximumApiVersion)
  }

  public convenience init(connection: Connection, mode: Mode) async {
    let store = try? ContentStore()
    await self.init(connection: connection, mode: mode, contentStore: store)
  }

  // Test seam: skips the backend-version discovery network call and accepts
  // a caller-provided URLSession (typically backed by `MockURLProtocol`).
  init(
    connection: Connection, mode: Mode, contentStore: ContentStore?,
    urlSession: URLSession, apiVersion: UInt? = nil,
    backendVersion: Version? = nil
  ) {
    self.connection = connection
    self.mode = mode
    self.contentStore = contentStore
    let delegate = PaperlessURLSessionDelegate(identityName: connection.identity)
    urlSessionDelegate = delegate
    self.urlSession = urlSession
    self.apiVersion = apiVersion
    self.backendVersion = backendVersion
  }

  init(connection: Connection, mode: Mode, contentStore: ContentStore?) async {
    self.connection = connection
    self.mode = mode
    self.contentStore = contentStore
    let sanitizedUrl = Self.sanitizeUrlForLog(connection.url)
    let tokenStr = sanitize(token: connection.token)
    Logger.networking.notice(
      "Initializing ApiRepository with connection \(sanitizedUrl, privacy: .public) and token \(tokenStr, privacy: .public)"
    )

    let delegate = PaperlessURLSessionDelegate(identityName: connection.identity)

    urlSessionDelegate = delegate
    urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

    if let versions = await Self.loadBackendVersions(urlSession: urlSession, connection: connection)
    {
      apiVersion = versions.apiVersion
      backendVersion = versions.backendVersion
    } else {
      apiVersion = nil
      backendVersion = nil
    }

    if let apiVersion, let backendVersion {
      Logger.networking.notice(
        "Backend version info: API version: \(apiVersion), backend version: \(backendVersion)")

      if apiVersion < Self.minimumApiVersion || Self.maximumApiVersion < apiVersion {
        let minimumApiVersion = Self.minimumApiVersion
        let maximumApiVersion = Self.maximumApiVersion
        Logger.networking.info(
          "Backend API version \(apiVersion) is outside of tested range of API versions [\(minimumApiVersion), \(maximumApiVersion)]"
        )
      }

    } else {
      Logger.networking.warning("Did not get backend version info")
    }
  }

  public nonisolated
    var delegate: (any URLSessionDelegate)?
  {
    urlSessionDelegate
  }

  private nonisolated
    var apiToken: String?
  {
    connection.token
  }

  public nonisolated
    func url(_ endpoint: Endpoint) throws -> URL
  {
    let connection = connection
    Logger.networking.trace("Making API endpoint URL with \(connection.url) for \(endpoint.path)")
    guard let url = endpoint.url(url: connection.url) else {
      let sanitizedUrl = Self.sanitizeUrlForLog(connection.url)
      Logger.networking.error("Unable to make URL: \(sanitizedUrl, privacy: .public)")
      throw RequestError.invalidRequest
    }
    return url
  }

  let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  public func request(url: URL) -> URLRequest {
    let sanitizedUrl = Self.sanitizeUrlForLog(url)
    var request = URLRequest(url: url)
    addTokenTo(request: &request)
    request.setValue(
      "application/json; version=\(effectiveApiVersion)", forHTTPHeaderField: "Accept")
    connection.extraHeaders.apply(toRequest: &request)
    let headerStr = sanitize(headers: request.allHTTPHeaderFields)
    Logger.networking.info(
      "Creating API request for URL \(sanitizedUrl, privacy: .public), headers: \(headerStr, privacy: .public)"
    )
    return request
  }

  public func request(_ endpoint: Endpoint) throws -> URLRequest {
    try request(url: url(endpoint))
  }

  private nonisolated
    static func sanitizeUrlForLog(_ url: URL) -> String
  {
    #if DEBUG
      return url.absoluteString
    #else
      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        Logger.networking.error("sanitizeUrlForLog failed")
        return "<private>"
      }

      components.host = "example.com"
      guard let result = components.url else {
        Logger.networking.error("sanitizeUrlForLog failed")
        return "<private>"
      }

      return result.absoluteString
    #endif
  }

  private nonisolated static func sentApiVersion(in request: URLRequest) -> UInt? {
    guard let accept = request.value(forHTTPHeaderField: "Accept"),
      let match = try? /version=(\d+)/.firstMatch(in: accept)
    else {
      return nil
    }
    return UInt(match.1)
  }

  static func sanitizedError(_ error: some Error, url: URL) -> String {
    #if DEBUG
      return String(describing: error)
    #else
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
      let scheme = components?.scheme ?? "http"
      return String(describing: error).replacingOccurrences(
        of: url.absoluteString, with: "\(scheme)://example.com")
    #endif
  }

  func fetchData(
    for request: URLRequest, expectedStatus: HTTPStatusCode = .ok,
    progress: (@Sendable (Double) -> Void)? = nil,
    cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
  ) async throws -> (Data, URLResponse) {
    try await Self.fetchData(
      for: request, expectedStatus: expectedStatus, progress: progress, cachePolicy: cachePolicy,
      urlSession: urlSession
    )
  }

  private static func fetchData(
    for request: URLRequest, expectedStatus: HTTPStatusCode = .ok,
    progress: (@Sendable (Double) -> Void)? = nil,
    cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData,
    urlSession: URLSession
  ) async throws -> (Data, URLResponse) {
    var request = request

    guard let url = request.url else {
      Logger.networking.error("Request URL is nil")
      throw RequestError.invalidRequest
    }

    let sanitizedUrl = Self.sanitizeUrlForLog(url)
    Logger.networking.info(
      "Fetching request data for \(request.httpMethod ?? "??", privacy: .public) \(sanitizedUrl, privacy: .public)"
    )

    let cachePolicyName =
      switch cachePolicy {
      case .useProtocolCachePolicy:
        "useProtocolCachePolicy"
      case .reloadIgnoringLocalCacheData:
        "reloadIgnoringLocalCacheData"
      case .reloadIgnoringLocalAndRemoteCacheData:
        "reloadIgnoringLocalAndRemoteCacheData"
      case .returnCacheDataElseLoad:
        "returnCacheDataElseLoad"
      case .returnCacheDataDontLoad:
        "returnCacheDataDontLoad"
      case .reloadRevalidatingCacheData:
        "reloadRevalidatingCacheData"
      @unknown default:
        "unknown"
      }

    Logger.networking.debug(
      "Using cache policy \(cachePolicyName, privacy: .public) for request \(sanitizedUrl, privacy: .public)"
    )
    request.cachePolicy = cachePolicy

    let result: (Data, URLResponse)
    do {
      result = try await urlSession.getData(for: request, progress: progress)
    } catch let error where error.isCancellationError {
      Logger.networking.info(
        "Fetch request task for \(request.httpMethod ?? "??", privacy: .public) \(sanitizedUrl, privacy: .public) was cancelled"
      )
      throw error
    } catch {
      let sanitizedError = sanitizedError(error, url: url)
      Logger.networking.error(
        "Caught error fetching \(sanitizedUrl, privacy: .public): \(sanitizedError, privacy: .public)"
      )
      throw error
    }

    let (data, response) = result

    Logger.networking.trace("Checking response of url \(sanitizedUrl, privacy: .public)")

    guard let response = response as? HTTPURLResponse, let status = response.status else {
      let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
      Logger.networking.error(
        "Response to \(sanitizedUrl, privacy: .public) is not HTTPURLResponse, body: \(body, privacy: .public)"
      )
      throw RequestError.invalidResponse
    }

    if status != expectedStatus {
      let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
      Logger.networking.error(
        "URLResponse to \(request.httpMethod ?? "???", privacy: .public) \(sanitizedUrl, privacy: .public) has status code \(response.statusCode) != \(expectedStatus), body: \(body, privacy: .public)"
      )

      switch status {
      case .forbidden:
        throw RequestError.forbidden(body: data)
      case .unauthorized:
        throw RequestError.unauthorized(body: data)
      case .notAcceptable:
        throw RequestError.unsupportedVersion(sentVersion: sentApiVersion(in: request))
      default:
        throw RequestError.unexpectedStatusCode(code: status, body: data)
      }
    }

    Logger.networking.trace(
      "URLResponse for \(sanitizedUrl, privacy: .public) has status code \(expectedStatus) as expected"
    )

    return (data, response)
  }

  @concurrent
  private nonisolated static func decodeBackground<T: Decodable & Sendable>(
    _ type: T.Type, from data: Data
  ) async throws -> T {
    try decoder.decode(type, from: data)
  }

  func fetchData<T: Decodable & Sendable>(
    for request: URLRequest, as type: T.Type,
    expectedStatus: HTTPStatusCode = .ok,
    progress: (@Sendable (Double) -> Void)? = nil,
    cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
  ) async throws -> T {
    let (data, _) = try await fetchData(
      for: request, expectedStatus: expectedStatus, progress: progress, cachePolicy: cachePolicy)
    do {
      return try await Self.decodeBackground(type, from: data)
    } catch let error as DecodingError {
      let sanitizedUrl =
        request.url.map(Self.sanitizeUrlForLog) ?? "<unknown>"
      let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
      if mode == .release {
        Logger.networking.error(
          "Unable to decode response to \(sanitizedUrl, privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .private): \(error)"
        )
      } else {
        let desc =
          "\(error.localizedDescription), \(error.errorDescription ?? "No error description")"
        Logger.networking.error(
          "Unable to decode response to \(sanitizedUrl, privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .public): \(error) \(desc, privacy: .public)"
        )

        switch error {
        case .typeMismatch(let type, let context):
          Logger.networking.error(
            "-> Type mismatch: \(type.self, privacy: .public) \(context.debugDescription, privacy: .public)"
          )
        case .valueNotFound(let type, let context):
          Logger.networking.error(
            "-> Value not found: \(type.self, privacy: .public) \(context.debugDescription, privacy: .public)"
          )
        case .keyNotFound(let key, let context):
          Logger.networking.error(
            "-> Key not found: \(key.debugDescription, privacy: .public) \(context.debugDescription, privacy: .public)"
          )
        case .dataCorrupted(let context):
          Logger.networking.error(
            "-> Data corrupted: \(type.self, privacy: .public) \(context.debugDescription, privacy: .public)"
          )
        default:
          Logger.networking.error("-> Unknown decoding error")
        }
      }
      throw DecodingErrorWithRootType(type: T.self, error: error)
    }
  }

  private func get<T: Decodable & Model & Sendable>(_ type: T.Type, id: UInt) async throws -> T? {
    try await get(type, endpoint: .single(T.self, id: id))
  }

  private func all<T>(_: T.Type) async throws -> [T]
  where T: Decodable & Model & Sendable {
    let endpoint: Endpoint =
      switch T.self {
      case is Correspondent.Type:
        .correspondents()
      case is DocumentType.Type:
        .documentTypes()
      case is Tag.Type:
        .tags()
      case is SavedView.Type:
        .savedViews()
      case is StoragePath.Type:
        .storagePaths()
      case is User.Type:
        .users()
      case is UserGroup.Type:
        .groups()
      case is CustomField.Type:
        .customFields()
      default:
        fatalError("Invalid type")
      }

    let cursor = try PageCursor<T>(
      repository: self,
      initialURL: url(endpoint))
    return try await cursor.collectAll()
  }

}

extension ApiRepository: Repository {
  public func update(document: Document) async throws -> Document {
    try await update(
      element: document,
      endpoint: .document(id: document.id, fullPerms: false))
  }

  public func create(document: ProtoDocument, file: URL, filename: String) async throws {
    Logger.networking.notice("Creating document")
    var request = try request(.createDocument())

    let mp = MultiPartFormDataRequest()
    mp.add(name: "title", string: document.title)

    if let corr = document.correspondent {
      mp.add(name: "correspondent", string: String(corr))
    }

    if let created = document.created {
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyy-MM-dd"
      let createdStr = formatter.string(from: created)
      mp.add(name: "created", string: createdStr)
    }

    if let dt = document.documentType {
      mp.add(name: "document_type", string: String(dt))
    }

    if let storagePath = document.storagePath {
      mp.add(name: "storage_path", string: String(storagePath))
    }

    if let asn = document.asn {
      mp.add(name: "archive_serial_number", string: String(asn))
    }

    for tag in document.tags {
      mp.add(name: "tags", string: String(tag))
    }

    try mp.add(name: "document", url: file, filename: filename)

    if supports(feature: .customFieldsOnCreate), !document.customFields.isEmpty {
      Logger.networking.debug("Adding custom fields to document create request")

      let encoded = try document.customFields.encodeToDictionary(encoder: encoder)
      if let encodedStr = String(data: encoded, encoding: .utf8) {
        mp.add(name: "custom_fields", string: encodedStr)
      } else {
        Logger.networking.error("Failed to encode custom fields to JSON")
      }
    }

    mp.addTo(request: &request)

    do {
      let _ = try await fetchData(for: request)
    } catch let RequestError.unexpectedStatusCode(code, _) where code == .contentTooLarge {
      throw DocumentCreateError.tooLarge
    } catch {
      Logger.networking.error("Error uploading document: \(error)")
      throw error
    }
  }

  public func delete(document: Document) async throws {
    Logger.networking.notice("Deleting document")
    try await delete(Document.self, endpoint: .document(id: document.id))
  }

  public func documents(filter: FilterState) throws -> any DocumentSource {
    Logger.networking.notice("Getting document sequence for filter")
    let cursor = try PageCursor<Document>(
      repository: self,
      initialURL: url(.documents(page: 1, filter: filter)))
    return ApiPagedSource<Document, Document>(cursor: cursor, map: { $0 })
  }

  public func download(
    documentID: UInt, original: Bool = false, progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    // No Document handle → no modified timestamp to validate the cache,
    // so always re-fetch. Callers should prefer download(document:...).
    try await streamDownload(
      documentID: documentID, original: original,
      modified: nil, progress: progress)
  }

  public func download(
    document: Document, original: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    try await streamDownload(
      documentID: document.id, original: original,
      modified: document.modified, progress: progress)
  }

  private func streamDownload(
    documentID: UInt, original: Bool,
    modified: Date?, progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    Logger.networking.notice("Downloading document (original: \(original))")

    guard let contentStore else {
      // App-group container unavailable (host tests, mis-configured entitlement).
      // Fall back to streaming straight to a temp file with no cache.
      return try await fetchToTemp(
        documentID: documentID, original: original, progress: progress)
    }

    let key = ContentStore.Key(
      serverID: connection.serverID,
      documentRemoteID: documentID,
      kind: original ? .original : .archive)

    if let cached = contentStore.read(key, freshAgainst: modified) {
      Logger.networking.info(
        "ContentStore hit for documentID \(documentID) (original: \(original))")
      progress?(1.0)
      return cached
    }

    if let existing = inFlightDownloads[key] {
      return try await existing.value
    }

    let task = Task<URL, Error> { [contentStore] in
      defer { inFlightDownloads[key] = nil }

      let request = try request(
        .download(documentId: documentID, original: original))
      let (tempURL, response) = try await urlSession.getDownload(
        for: request, progress: progress)

      try validateDownloadResponse(response, request: request)

      return try contentStore.store(
        key, movingFrom: tempURL, modified: modified)
    }
    inFlightDownloads[key] = task
    return try await task.value
  }

  private func fetchToTemp(
    documentID: UInt, original: Bool,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    let request = try request(
      .download(documentId: documentID, original: original))
    let (tempURL, response) = try await urlSession.getDownload(
      for: request, progress: progress)
    try validateDownloadResponse(response, request: request)

    let dest = URL(
      fileURLWithPath: NSTemporaryDirectory(), isDirectory: true
    ).appendingPathComponent(
      response.suggestedFilename ?? "document.pdf")
    if FileManager.default.fileExists(atPath: dest.path) {
      _ = try FileManager.default.replaceItemAt(dest, withItemAt: tempURL)
    } else {
      try FileManager.default.moveItem(at: tempURL, to: dest)
    }
    return dest
  }

  private nonisolated func validateDownloadResponse(
    _ response: URLResponse, request: URLRequest
  ) throws {
    guard let http = response as? HTTPURLResponse, let status = http.status else {
      throw RequestError.invalidResponse
    }
    guard status == .ok else {
      switch status {
      case .forbidden:
        throw RequestError.forbidden(body: Data())
      case .unauthorized:
        throw RequestError.unauthorized(body: Data())
      case .notAcceptable:
        throw RequestError.unsupportedVersion(sentVersion: nil)
      default:
        throw RequestError.unexpectedStatusCode(code: status, body: Data())
      }
    }
  }

  public func tag(id: UInt) async throws -> Tag? {
    try await get(ApiTag.self, endpoint: .tag(id: id))?.domain
  }

  public func create(tag: ProtoTag) async throws -> Tag {
    let apiTag: ApiTag = try await create(
      element: ApiTagCreate(from: tag), endpoint: .createTag(), returns: ApiTag.self)
    return apiTag.domain
  }

  public func update(tag: Tag) async throws -> Tag {
    let apiTag: ApiTag = try await update(
      element: ApiTagUpdate(from: tag), endpoint: .tag(id: tag.id), returns: ApiTag.self)
    return apiTag.domain
  }

  public func delete(tag: Tag) async throws {
    try await delete(Tag.self, endpoint: .tag(id: tag.id))
  }

  public func tags() async throws -> [Tag] {
    let cursor = try PageCursor<ApiTag>(
      repository: self,
      initialURL: url(.tags()))
    return try await cursor.collectAll().flattenedUnique.map(\.domain)
  }

  public func correspondent(id: UInt) async throws -> Correspondent? {
    try await get(Correspondent.self, id: id)
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    try await create(
      element: correspondent,
      endpoint: .createCorrespondent(),
      returns: Correspondent.self)
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    try await update(
      element: correspondent,
      endpoint: .correspondent(id: correspondent.id))
  }

  public func delete(correspondent: Correspondent) async throws {
    try await delete(Correspondent.self, endpoint: .correspondent(id: correspondent.id))
  }

  public func correspondents() async throws -> [Correspondent] { try await all(Correspondent.self) }

  public func documentType(id: UInt) async throws -> DocumentType? {
    try await get(DocumentType.self, id: id)
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    try await create(
      element: documentType,
      endpoint: .createDocumentType(),
      returns: DocumentType.self)
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    try await update(
      element: documentType,
      endpoint: .documentType(id: documentType.id))
  }

  public func delete(documentType: DocumentType) async throws {
    try await delete(DocumentType.self, endpoint: .documentType(id: documentType.id))
  }

  public func documentTypes() async throws -> [DocumentType] { try await all(DocumentType.self) }

  public func document(id: UInt) async throws -> Document? { try await get(Document.self, id: id) }

  public func document(asn: UInt) async throws -> Document? {
    Logger.networking.notice("Getting document by ASN")

    let rule = FilterRule(ruleType: .asn, value: .number(value: Int(asn)))!
    let decoded = try await send(
      endpoint: .documents(page: 1, rules: [rule]),
      returns: ListResponse<Document>.self)

    guard decoded.count > 0, !decoded.results.isEmpty else {
      Logger.networking.notice("Got empty document result (ASN not found)")
      return nil
    }
    return decoded.results.first
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    try await send(endpoint: .metadata(documentId: documentId), returns: Metadata.self)
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    try await send(endpoint: .notes(documentId: documentId), returns: [Document.Note].self)
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note]
  {
    try await send(
      .post,
      endpoint: .notes(documentId: documentId),
      body: note,
      returns: [Document.Note].self)
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    try await send(
      .delete,
      endpoint: .note(documentId: documentId, noteId: id),
      returns: [Document.Note].self)
  }

  public func trash() async throws -> [Document] {
    Logger.networking.notice("Getting trash documents")
    let endpoint = Endpoint.trash(page: 1, pageSize: 100_000)
    let cursor = try PageCursor<Document>(repository: self, initialURL: url(endpoint))
    return try await cursor.collectAll()
  }

  private enum TrashAction: String, Encodable {
    case restore
    case empty
  }

  private struct TrashActionRequest: Encodable {
    let action: TrashAction
    let documents: [UInt]
  }

  public func restoreTrash(documents: [UInt]) async throws {
    try await performTrashAction(.restore, documents: documents)
  }

  public func emptyTrash(documents: [UInt]) async throws {
    try await performTrashAction(.empty, documents: documents)
  }

  private func performTrashAction(_ action: TrashAction, documents: [UInt]) async throws {
    Logger.networking.notice("Sending trash action \(action.rawValue)")
    try await send(
      .post,
      endpoint: .trash(),
      body: TrashActionRequest(action: action, documents: documents))
  }

  private func nextAsnCompatibility() async throws -> UInt {
    Logger.networking.notice("Getting next ASN with legacy compatibility method")

    let decoded = try await send(
      endpoint: .documents(page: 1, filter: .empty, pageSize: 1),
      returns: ListResponse<Document>.self)
    return (decoded.results.first?.asn ?? 0) + 1
  }

  private func nextAsnDirectEndpoint() async throws -> UInt {
    Logger.networking.notice("Getting next ASN with dedicated endpoint")
    let asn = try await send(endpoint: .nextAsn(), returns: UInt.self)
    Logger.networking.notice("Have next ASN \(asn)")
    return asn
  }

  public func nextAsn() async throws -> UInt {
    if supports(feature: .nextAsnEndpoint) {
      try await nextAsnDirectEndpoint()
    } else {
      try await nextAsnCompatibility()
    }
  }

  public func users() async throws -> [User] { try await all(User.self) }

  public func groups() async throws -> [UserGroup] { try await all(UserGroup.self) }

  public func thumbnail(document: Document) async throws -> Image? {
    let data = try await thumbnailData(document: document)
    guard let image = Image(data: data) else {
      Logger.networking.error("Thumbnail data did not decode as image")
      return nil
    }
    return image
  }

  public func thumbnailData(document: Document) async throws -> Data {
    let request = try thumbnailRequest(document: document)
    do {
      let (data, _) = try await fetchData(for: request, cachePolicy: .returnCacheDataElseLoad)
      return data
    } catch is CancellationError {
      Logger.networking.trace("Thumbnail data request task was cancelled")
      throw CancellationError()
    } catch {
      Logger.networking.error(
        "Error getting thumbnail data for document \(document.id, privacy: .public): \(error)")
      throw error
    }
  }

  private nonisolated
    func addTokenTo(request: inout URLRequest)
  {
    Self.addTokenTo(request: &request, token: connection.token)
  }

  private nonisolated
    static func addTokenTo(request: inout URLRequest, token: String?)
  {
    let tokenStr = sanitize(token: token)
    if let token {
      Logger.networking.debug("Adding token to request: \(tokenStr, privacy: .public)")
      request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
    } else {
      Logger.networking.info("NOT adding token to request (token is nil)")
    }
  }

  public nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest
  {
    Logger.networking.debug("Get thumbnail for document \(document.id, privacy: .public)")
    let url = try url(Endpoint.thumbnail(documentId: document.id))

    var request = URLRequest(url: url)
    addTokenTo(request: &request)
    connection.extraHeaders.apply(toRequest: &request)

    return request
  }

  public func suggestions(documentId: UInt) async throws -> Suggestions {
    Logger.networking.notice("Get suggestions")
    return try await send(
      endpoint: .suggestions(documentId: documentId), returns: Suggestions.self)
  }

  // MARK: Saved views

  public func savedViews() async throws -> [SavedView] {
    try await all(SavedView.self)
  }

  public func create(savedView view: ProtoSavedView) async throws -> SavedView {
    try await create(element: view, endpoint: .createSavedView(), returns: SavedView.self)
  }

  public func update(savedView view: SavedView) async throws -> SavedView {
    try await update(element: view, endpoint: .savedView(id: view.id))
  }

  public func delete(savedView view: SavedView) async throws {
    try await delete(SavedView.self, endpoint: .savedView(id: view.id))
  }

  // MARK: Storage paths

  public func storagePaths() async throws -> [StoragePath] {
    try await all(StoragePath.self)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    try await create(
      element: storagePath, endpoint: .createStoragePath(), returns: StoragePath.self)
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    try await update(element: storagePath, endpoint: .storagePath(id: storagePath.id))
  }

  public func delete(storagePath: StoragePath) async throws {
    try await delete(StoragePath.self, endpoint: .storagePath(id: storagePath.id))
  }

  // MARK: Custom fields

  public func customFields() async throws -> [CustomField] {
    try await all(CustomField.self)
  }

  // MARK: Server configuration

  public func serverConfiguration() async throws -> ServerConfiguration {
    let configurations = try await send(
      endpoint: .appConfiguration(), returns: [ServerConfiguration].self)

    guard let firstConfig = configurations.first else {
      Logger.networking.error("No server configuration found")
      throw RequestError.invalidResponse
    }

    return firstConfig
  }

  public func remoteVersion() async throws -> RemoteVersion {
    try await send(endpoint: .remoteVersion(), returns: RemoteVersion.self)
  }

  // MARK: Others

  public func currentUser() async throws -> User {
    try await uiSettings().user
  }

  public func uiSettings() async throws -> UISettings {
    try await send(endpoint: .uiSettings(), returns: ApiUISettings.self).domain
  }

  public func update(settings: UISettingsSettings) async throws {
    struct UISettingsPayload: Encodable {
      let settings: ApiUISettingsSettings
    }

    try await send(
      .post, endpoint: .uiSettings(),
      body: UISettingsPayload(settings: ApiUISettingsSettings(from: settings)))
  }

  public func tasks(limit: UInt) async throws -> [PaperlessTask] {
    if supports(feature: .taskListEnvelope) {
      return try await send(
        endpoint: .tasks(name: .consumeFile, acknowledged: false, pageSize: limit),
        returns: ListResponse<ApiTaskV10>.self
      ).results.map(\.domain)
    } else {
      // V9 backends do not paginate the tasks endpoint; the limit is ignored.
      return try await send(
        endpoint: .tasks(name: .consumeFile, acknowledged: false),
        returns: [ApiTaskV9].self
      ).map(\.domain)
    }
  }

  public func tasks() throws -> any TaskSource {
    if supports(feature: .taskListEnvelope) {
      let initial = try url(.tasks(name: .consumeFile, acknowledged: false, pageSize: 100))
      let cursor = PageCursor<ApiTaskV10>(repository: self, initialURL: initial)
      return ApiPagedSource<ApiTaskV10, PaperlessTask>(cursor: cursor, map: { $0.domain })
    } else {
      return ApiTaskSourceV9(repository: self)
    }
  }

  public func task(id: UInt) async throws -> PaperlessTask? {
    do {
      if supports(feature: .taskListEnvelope) {
        return try await send(endpoint: .task(id: id), returns: ApiTaskV10.self).domain
      } else {
        return try await send(endpoint: .task(id: id), returns: ApiTaskV9.self).domain
      }
    } catch RequestError.unexpectedStatusCode(code: .notFound, _) {
      return nil
    }
  }

  public func acknowledge(tasks ids: [UInt]) async throws {
    let endpoint: Endpoint =
      if supports(feature: .taskAcknowledgeEndpoint) {
        .acknowlegdeTasks()
      } else {
        .acknowlegdeTasksV1()
      }

    try await send(.post, endpoint: endpoint, body: ["tasks": ids])
  }

  private static func loadBackendVersions(urlSession: URLSession, connection: Connection) async -> (
    apiVersion: UInt, backendVersion: Version
  )? {
    Logger.networking.info("Getting backend versions")
    do {
      // @TODO: Maybe switch to `/api/remote_version`

      guard let url = Endpoint.uiSettings().url(url: connection.url) else {
        Logger.networking.error("Unable to create URL for determining backend version")
        return nil
      }

      var request = URLRequest(url: url)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      Self.addTokenTo(request: &request, token: connection.token)
      connection.extraHeaders.apply(toRequest: &request)

      // Use the raw URLSession directly: paperless-ngx sets X-Version / X-Api-Version on every
      // response via middleware, so we want to read them even when the body request would have
      // failed (e.g. the authenticated user lacks permissions to view /api/ui_settings/, which
      // would otherwise throw forbidden before we ever see the headers).
      let (_, res) = try await urlSession.getData(for: request)

      guard let res = res as? HTTPURLResponse else {
        Logger.networking.error("Unable to get API and backend version: Not an HTTP response")
        return nil
      }

      if res.statusCode != 200 {
        Logger.networking.warning(
          "Status code for version request was \(res.statusCode), not 200 — continuing with version headers from the response anyway."
        )
      }

      let backend1 = res.value(forHTTPHeaderField: "X-Version")
      let backend2 = res.value(forHTTPHeaderField: "x-version")

      guard let backend1, let backend2 else {
        Logger.networking.error("Unable to get API and backend version: X-Version not found")
        return nil
      }
      let backend = [backend1, backend2].compactMap { $0 }.first!

      guard let backendVersion = Version(backend) else {
        Logger.networking.error("Unable to get API and backend version: Invalid format \(backend)")
        return nil
      }

      guard let apiVersion = res.value(forHTTPHeaderField: "X-Api-Version"),
        let apiVersion = UInt(apiVersion)
      else {
        Logger.networking.error("Unable to get API and backend version: X-Api-Version not found")
        return nil
      }

      return (apiVersion, backendVersion)
    } catch {
      Logger.networking.error(
        "Unable to get API and backend version, error: \(String(describing: error))")
      return nil
    }
  }

  public func supports(feature: BackendFeature) -> Bool {
    guard let backendVersion, let apiVersion else { return false }
    return feature.isSupported(on: backendVersion, api: apiVersion)
  }

  // MARK: - Share links

  public func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink] {
    try await send(
      endpoint: .shareLinks(documentId: documentId),
      returns: [DataModel.ShareLink].self)
  }

  public func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink {
    try await create(
      element: shareLink, endpoint: .createShareLink(), returns: ShareLink.self)
  }

  public func delete(shareLink: DataModel.ShareLink) async throws {
    try await delete(ShareLink.self, endpoint: .shareLink(id: shareLink.id))
  }
}
