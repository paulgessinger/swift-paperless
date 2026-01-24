//
//  ApiRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import AsyncAlgorithms
import Common
import DataModel
import Foundation
import Semaphore
import SwiftUI
import os

public actor ApiDocumentSource: DocumentSource {
  public typealias DocumentSequence = ApiSequence<Document>

  private let sequence: DocumentSequence

  public init(sequence: DocumentSequence) {
    self.sequence = sequence
  }

  public func fetch(limit: UInt) async throws -> [Document] {
    guard await sequence.hasMore else {
      return []
    }
    return try await Array(sequence.prefix(Int(limit)))
  }

  public func hasMore() async -> Bool { await sequence.hasMore }
}

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

  nonisolated
    private let apiVersion: UInt?
  nonisolated
    public static let minimumApiVersion: UInt = 3
  nonisolated
    public static let minimumVersion = Version(1, 14, 1)
  nonisolated
    public static let maximumApiVersion: UInt = 9
  nonisolated
    public let backendVersion: Version?

  public var effectiveApiVersion: UInt {
    min(Self.maximumApiVersion, max(Self.minimumApiVersion, apiVersion ?? Self.minimumApiVersion))
  }

  public init(connection: Connection, mode: Mode) async {
    self.connection = connection
    self.mode = mode
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

  private func fetchData(
    for request: URLRequest, code: HTTPStatusCode = .ok,
    progress: (@Sendable (Double) -> Void)? = nil,
    cachePolicy: URLRequest.CachePolicy = .reloadIgnoringLocalCacheData
  ) async throws -> (Data, URLResponse) {
    try await Self.fetchData(
      for: request, code: code, progress: progress, cachePolicy: cachePolicy, urlSession: urlSession
    )
  }

  private static func fetchData(
    for request: URLRequest, code: HTTPStatusCode = .ok,
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

    if status != code {
      let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
      Logger.networking.error(
        "URLResponse to \(request.httpMethod ?? "???", privacy: .public) \(sanitizedUrl, privacy: .public) has status code \(response.statusCode) != \(code), body: \(body, privacy: .public)"
      )

      switch status {
      case .forbidden:
        throw RequestError.forbidden(body: data)
      case .unauthorized:
        throw RequestError.unauthorized(body: data)
      case .notAcceptable:
        throw RequestError.unsupportedVersion
      default:
        throw RequestError.unexpectedStatusCode(code: status, body: data)
      }
    }

    Logger.networking.trace(
      "URLResponse for \(sanitizedUrl, privacy: .public) has status code \(code) as expected")

    return (data, response)
  }

  func fetchData<T: Decodable>(for request: URLRequest, as type: T.Type, code: HTTPStatusCode = .ok)
    async throws -> T
  {
    let (data, _) = try await fetchData(for: request, code: code)
    do {
      return try decoder.decode(type, from: data)
    } catch let error as DecodingError {
      let url = request.url!
      let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
      if mode == .release {
        Logger.networking.error(
          "Unable to decode response to \(Self.sanitizeUrlForLog(url), privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .private): \(error)"
        )
      } else {
        let desc =
          "\(error.localizedDescription), \(error.errorDescription ?? "No error description")"
        Logger.networking.error(
          "Unable to decode response to \(Self.sanitizeUrlForLog(url), privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .public): \(error) \(desc, privacy: .public)"
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

  private func get<T: Decodable & Model>(_ type: T.Type, id: UInt) async throws -> T? {
    let request = try request(.single(T.self, id: id))

    do {
      return try await fetchData(for: request, as: type)
    } catch {
      Logger.networking.error(
        "Error getting \(type, privacy: .public) with id \(id, privacy: .public): \(error)")
      return nil
    }
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

    let sequence = try ApiSequence<T>(
      repository: self,
      url: url(endpoint))
    return try await Array(sequence)
  }

  private func create<Element>(element: some Encodable, endpoint: Endpoint, returns: Element.Type)
    async throws -> Element where Element: Decodable
  {
    var request = try request(endpoint)

    let body = try encoder.encode(element)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      let (data, _) = try await fetchData(for: request, code: .created)

      let created = try decoder.decode(returns, from: data)
      return created
    } catch {
      Logger.networking.error("Api create \(returns) failed: \(error)")
      throw error
    }
  }

  private func update<Element>(element: Element, endpoint: Endpoint) async throws -> Element
  where Element: Codable {
    var request = try request(endpoint)

    let body = try encoder.encode(element)
    request.httpMethod = "PATCH"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      return try await fetchData(for: request, as: Element.self)
    } catch {
      Logger.networking.error("Api update \(Element.self) failed: \(error)")
      throw error
    }
  }

  private func delete<Element>(element _: Element, endpoint: Endpoint) async throws {
    var request = try request(endpoint)
    request.httpMethod = "DELETE"

    do {
      _ = try await fetchData(for: request, code: .noContent)
    } catch {
      Logger.networking.error("Api delete \(Element.self) failed: \(error)")
      throw error
    }
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

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let createdStr = formatter.string(from: document.created)
    mp.add(name: "created", string: createdStr)

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
      let _ = try await fetchData(for: request, code: .ok)
    } catch let RequestError.unexpectedStatusCode(code, _) where code == .contentTooLarge {
      throw DocumentCreateError.tooLarge
    } catch {
      Logger.networking.error("Error uploading document: \(error)")
      throw error
    }
  }

  public func delete(document: Document) async throws {
    Logger.networking.notice("Deleting document")
    try await delete(element: document, endpoint: .document(id: document.id))
  }

  public func documents(filter: FilterState) throws -> any DocumentSource {
    Logger.networking.notice("Getting document sequence for filter")
    return try ApiDocumentSource(
      sequence: ApiSequence<Document>(
        repository: self,
        url: url(.documents(page: 1, filter: filter))))
  }

  public func download(documentID: UInt, progress: (@Sendable (Double) -> Void)? = nil) async throws
    -> URL?
  {
    Logger.networking.notice("Downloading document")
    do {
      let request = try request(.download(documentId: documentID))

      let (data, response) = try await fetchData(
        for: request, code: .ok,
        progress: progress)

      guard let suggestedFilename = response.suggestedFilename else {
        Logger.networking.error("Cannot get suggested filename from response")
        return nil
      }

      let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(suggestedFilename)

      try data.write(to: temporaryFileURL, options: .atomic)
      try await Task.sleep(for: .seconds(0.2))  // wait a little bit for the data to be flushed
      return temporaryFileURL

    } catch {
      Logger.networking.error("Error downloading document: \(error)")
      return nil
    }
  }

  public func tag(id: UInt) async throws -> Tag? { try await get(Tag.self, id: id) }

  public func create(tag: ProtoTag) async throws -> Tag {
    try await create(element: tag, endpoint: .createTag(), returns: Tag.self)
  }

  public func update(tag: Tag) async throws -> Tag {
    try await update(element: tag, endpoint: .tag(id: tag.id))
  }

  public func delete(tag: Tag) async throws {
    try await delete(element: tag, endpoint: .tag(id: tag.id))
  }

  public func tags() async throws -> [Tag] { try await all(Tag.self) }

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
    try await delete(
      element: correspondent,
      endpoint: .correspondent(id: correspondent.id))
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
    try await delete(
      element: documentType,
      endpoint: .documentType(id: documentType.id))
  }

  public func documentTypes() async throws -> [DocumentType] { try await all(DocumentType.self) }

  public func document(id: UInt) async throws -> Document? { try await get(Document.self, id: id) }

  public func document(asn: UInt) async throws -> Document? {
    Logger.networking.notice("Getting document by ASN")

    let rule = FilterRule(ruleType: .asn, value: .number(value: Int(asn)))!
    let endpoint = Endpoint.documents(page: 1, rules: [rule])

    let request = try request(endpoint)

    do {
      let decoded = try await fetchData(for: request, as: ListResponse<Document>.self)

      guard decoded.count > 0, !decoded.results.isEmpty else {
        // this means the ASN was not found
        Logger.networking.notice("Got empty document result (ASN not found)")
        return nil
      }
      return decoded.results.first

    } catch {
      Logger.networking.error("Error fetching document by ASN \(asn): \(error)")
      return nil
    }
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    let request = try request(.metadata(documentId: documentId))
    do {
      let decoded = try await fetchData(for: request, as: Metadata.self)
      return decoded
    } catch {
      Logger.networking.error("Error fetching document metadata for id \(documentId): \(error)")
      throw error
    }
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    let request = try request(.notes(documentId: documentId))
    do {
      return try await fetchData(for: request, as: [Document.Note].self, code: .ok)
    } catch {
      Logger.networking.error("Error fetching notes for document \(documentId): \(error)")
      throw error
    }
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note]
  {
    var request = try request(.notes(documentId: documentId))
    let body = try encoder.encode(note)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      return try await fetchData(for: request, as: [Document.Note].self, code: .ok)
    } catch {
      Logger.networking.error("Error creating note on document \(documentId): \(error)")
      throw error
    }
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    var request = try request(.note(documentId: documentId, noteId: id))
    request.httpMethod = "DELETE"

    do {
      return try await fetchData(for: request, as: [Document.Note].self, code: .ok)
    } catch {
      Logger.networking.error("Error deleting note on document \(documentId): \(error)")
      throw error
    }
  }

  public func trash() async throws -> [Document] {
    Logger.networking.notice("Getting trash documents")
    let endpoint = Endpoint.trash(page: 1, pageSize: 100_000)
    let sequence = try ApiSequence<Document>(repository: self, url: url(endpoint))
    return try await Array(sequence)
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
    var request = try request(.trash())
    let payload = TrashActionRequest(action: action, documents: documents)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try encoder.encode(payload)

    do {
      _ = try await fetchData(for: request, code: .ok)
    } catch {
      Logger.networking.error("Trash action \(action.rawValue) failed: \(error)")
      throw error
    }
  }

  private func nextAsnCompatibility() async throws -> UInt {
    Logger.networking.notice("Getting next ASN with legacy compatibility method")

    let endpoint = Endpoint.documents(page: 1, filter: .empty, pageSize: 1)
    let url = try url(endpoint)
    Logger.networking.notice("\(url)")

    let request = try request(endpoint)

    do {
      let decoded = try await fetchData(for: request, as: ListResponse<Document>.self)

      return (decoded.results.first?.asn ?? 0) + 1
    } catch {
      Logger.networking.error("Error fetching document for next ASN: \(error)")
    }

    return 0
  }

  private func nextAsnDirectEndpoint() async throws -> UInt {
    Logger.networking.notice("Getting next ASN with dedicated endpoint")
    let request = try request(.nextAsn())

    do {
      let asn = try await fetchData(for: request, as: UInt.self)
      Logger.networking.notice("Have next ASN \(asn)")
      return asn
    } catch {
      Logger.networking.error("Error fetching next ASN: \(error)")
      return 0
    }
  }

  public func nextAsn() async throws -> UInt {
    if let backendVersion, backendVersion >= Version(2, 0, 0) {
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
    let request = try request(.suggestions(documentId: documentId))

    do {
      return try await fetchData(for: request, as: Suggestions.self)
    } catch {
      Logger.networking.error("Unable to load suggestions: \(error)")
      return .init()
    }
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
    try await delete(element: view, endpoint: .savedView(id: view.id))
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
    try await delete(element: storagePath, endpoint: .storagePath(id: storagePath.id))
  }

  // MARK: Custom fields

  public func customFields() async throws -> [CustomField] {
    try await all(CustomField.self)
  }

  // MARK: Server configuration

  public func serverConfiguration() async throws -> ServerConfiguration {
    let request = try request(.appConfiguration())
    let configurations = try await fetchData(for: request, as: [ServerConfiguration].self)

    guard let firstConfig = configurations.first else {
      Logger.networking.error("No server configuration found")
      throw RequestError.invalidResponse
    }

    return firstConfig
  }

  public func remoteVersion() async throws -> RemoteVersion {
    let request = try request(.remoteVersion())
    return try await fetchData(for: request, as: RemoteVersion.self)

  }

  // MARK: Others

  public func currentUser() async throws -> User {
    try await uiSettings().user
  }

  public func uiSettings() async throws -> UISettings {
    let request = try request(.uiSettings())
    return try await fetchData(for: request, as: UISettings.self)
  }

  public func tasks() async throws -> [PaperlessTask] {
    let request = try request(.tasks(name: .consumeFile, acknowledged: false))

    do {
      return try await fetchData(for: request, as: [PaperlessTask].self)
    } catch {
      Logger.networking.error("Unable to load tasks: \(error)")
      throw error
    }
  }

  public func task(id: UInt) async throws -> PaperlessTask? {
    let request = try request(.task(id: id))

    return try await fetchData(for: request, as: PaperlessTask.self)
  }

  public func acknowledge(tasks ids: [UInt]) async throws {
    let endpoint: Endpoint =
      if let backendVersion, backendVersion >= Version(2, 14, 0) {
        .acknowlegdeTasks()
      } else {
        .acknowlegdeTasksV1()
      }

    var request = try request(endpoint)

    let payload: [String: [UInt]] = ["tasks": ids]

    let body = try encoder.encode(payload)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = body

    do {
      _ = try await fetchData(for: request, code: .ok)
    } catch {
      Logger.networking.error("Api acknowledge failed: \(error)")
      throw error
    }
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
      Self.addTokenTo(request: &request, token: connection.token)
      connection.extraHeaders.apply(toRequest: &request)

      let (_, res) = try await Self.fetchData(for: request, urlSession: urlSession)

      // fetchData should have already ensured this
      guard let res = res as? HTTPURLResponse else {
        Logger.networking.error("Unable to get API and backend version: Not an HTTP response")
        return nil
      }

      if res.statusCode != 200 {
        Logger.networking.error(
          "Status code for version request was \(res.statusCode), not 200. Usually this means authentication is broken."
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
    guard let backendVersion else { return false }
    return feature.isSupported(on: backendVersion)
  }

  // MARK: - Share links

  public func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink] {
    do {
      let request = try request(.shareLinks(documentId: documentId))
      return try await fetchData(for: request, as: [DataModel.ShareLink].self)
    } catch {
      Logger.networking.error("Getting share links for document \(documentId) failed: \(error)")
      throw error
    }
  }

  public func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink {
    try await create(
      element: shareLink, endpoint: .createShareLink(), returns: ShareLink.self)
  }

  public func delete(shareLink: DataModel.ShareLink) async throws {
    try await delete(element: shareLink, endpoint: .shareLink(id: shareLink.id))
  }
}
