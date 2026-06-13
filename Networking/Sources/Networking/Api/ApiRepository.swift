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

  // Detected API/backend versions. Mutable because detection can be re-run at
  // runtime: if the backend is unreachable at init we lock in the minimum API
  // version, and a later 406 (`unsupportedVersion`) triggers a re-probe so the
  // repository recovers once the backend comes back online.
  private var apiVersion: UInt?
  nonisolated
    public static let minimumApiVersion: UInt = 3
  nonisolated
    public static let minimumVersion = Version(1, 14, 1)
  nonisolated
    public static let maximumApiVersion: UInt = 10
  public private(set) var backendVersion: Version?

  // Single-flight guard for runtime re-probing: when several in-flight requests
  // 406 at once (e.g. the backend just came back online) they share one probe
  // rather than each hammering the backend through the full version sweep.
  private var versionReprobeTask: Task<UInt?, Never>?

  public var effectiveApiVersion: UInt {
    // If X-Api-Version can't be read (e.g. 401 before middleware), apiVersion is nil.
    // Defaulting to minimumApiVersion ensures compatibility and lets the app handle real 401s for user recovery.
    min(Self.maximumApiVersion, apiVersion ?? Self.minimumApiVersion)
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
    } else if let detected = await Self.iterateAcceptedApiVersion(
      urlSession: urlSession, connection: connection)
    {
      // Header probe failed; tried Accept versions until backend responded. No backend version string learned; feature support is conservative until successful header probe.
      apiVersion = detected
      backendVersion = nil
      Logger.networking.notice(
        "Header probe failed; iteration probe selected API version \(detected)")
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
    do {
      return try await Self.fetchData(
        for: request, expectedStatus: expectedStatus, progress: progress, cachePolicy: cachePolicy,
        urlSession: urlSession
      )
    } catch RequestError.unsupportedVersion(let sentVersion) {
      // The backend rejected our API version. This is the recovery path for a
      // version that was locked in against an unreachable backend (app launched
      // offline → minimum API version). Re-probe the live backend; if a
      // different version comes back, retry the request once with a corrected
      // Accept header. The retried call goes straight to the static helper, so a
      // second 406 propagates instead of looping.
      Logger.networking.warning(
        "Request rejected as unsupported API version (sent \(String(describing: sentVersion), privacy: .public)); re-probing backend"
      )

      guard await reprobeVersion() != nil else {
        Logger.networking.error(
          "Re-probe failed to detect a working API version; propagating unsupportedVersion")
        throw RequestError.unsupportedVersion(sentVersion: sentVersion)
      }

      let retryVersion = effectiveApiVersion
      guard retryVersion != sentVersion else {
        Logger.networking.error(
          "Re-probe yielded the same API version (\(retryVersion)); propagating unsupportedVersion to avoid a retry loop"
        )
        throw RequestError.unsupportedVersion(sentVersion: sentVersion)
      }

      Logger.networking.notice(
        "Re-probe selected API version \(retryVersion); retrying request once")
      var retry = request
      retry.setValue(
        "application/json; version=\(retryVersion)", forHTTPHeaderField: "Accept")
      return try await Self.fetchData(
        for: retry, expectedStatus: expectedStatus, progress: progress,
        cachePolicy: cachePolicy, urlSession: urlSession
      )
    }
  }

  // Re-runs API-version detection after the backend rejected a request with 406
  // (`unsupportedVersion`) — typically because the version was locked in while
  // the backend was unreachable. Updates `apiVersion`/`backendVersion` in place
  // and returns the detected API version, or nil if detection failed (e.g. the
  // backend is still unreachable). Concurrent callers share one in-flight probe.
  private func reprobeVersion() async -> UInt? {
    if let versionReprobeTask {
      return await versionReprobeTask.value
    }

    let task = Task<UInt?, Never> {
      if let versions = await Self.loadBackendVersions(
        urlSession: urlSession, connection: connection)
      {
        apiVersion = versions.apiVersion
        backendVersion = versions.backendVersion
        return versions.apiVersion
      }
      if let detected = await Self.iterateAcceptedApiVersion(
        urlSession: urlSession, connection: connection)
      {
        // The iteration probe can't learn the backend version string; keep any
        // previously-known value rather than clobbering feature support to nil.
        apiVersion = detected
        return detected
      }
      return nil
    }

    versionReprobeTask = task
    defer { versionReprobeTask = nil }
    return await task.value
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

    // Best-effort data-transfer accounting (categorised by the caller's
    // task-local). Counts JSON/list responses only; downloads/thumbnails differ.
    NetworkTransfer.record(bytes: data.count)

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

}

extension ApiRepository: Repository {
  public func update(document: Document) async throws -> Document {
    let api: ApiDocument = try await update(
      element: ApiDocumentUpdate(from: document),
      endpoint: .document(id: document.id, fullPerms: false),
      returns: ApiDocument.self)
    return api.domain
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

  public func documents(filter: FilterState) throws -> ApiPagedSource<ApiDocument, Document> {
    Logger.networking.notice("Getting document sequence for filter")
    // The full list shape always carries object detail (`full_perms`), so every
    // cached row is renderable offline without a per-document round-trip.
    let cursor = try PageCursor<ApiDocument>(
      repository: self,
      initialURL: url(.documents(page: 1, filter: filter)))
    return ApiPagedSource<ApiDocument, Document>(cursor: cursor, map: { $0.domain })
  }

  /// Cheap id-only projection (`fields=id`) in a few very large pages — the
  /// authoritative ordered id set for the remote-delete reconcile.
  public func documentIDs(filter: FilterState) async throws -> [UInt] {
    Logger.networking.notice("Getting document id set for filter")
    let cursor = try PageCursor<ApiDocumentID>(
      repository: self,
      initialURL: url(.documents(page: 1, filter: filter, pageSize: 25000, fields: ["id"])))
    return try await cursor.collectAll().map(\.id)
  }

  public func download(
    document: Document, original: Bool = false,
    progress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> URL {
    try await streamDownload(document: document, original: original, progress: progress)
  }

  private func streamDownload(
    document: Document, original: Bool,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    Logger.networking.notice("Downloading document (original: \(original))")

    let version = document.currentVersionID

    // Without a staleness signal (modified timestamp) we can't validate a
    // cached blob — and writing one back without `modified` would cache it
    // indefinitely with no way to detect server-side changes. Bypass the
    // ContentStore entirely in that case. Also fall back when the app-group
    // container isn't available (host tests, mis-configured entitlement).
    guard let contentStore, let modified = document.modified else {
      return try await fetchToTemp(
        documentID: document.id, original: original, version: version,
        progress: progress)
    }

    let key = ContentStore.Key(
      serverID: connection.serverID,
      versionID: version,
      kind: original ? .original : .archive)

    if let cached = contentStore.read(key, freshAgainst: modified) {
      Logger.networking.info(
        "ContentStore hit for documentID \(document.id) version \(version) (original: \(original))"
      )
      progress?(1.0)
      return cached
    }

    if let existing = inFlightDownloads[key] {
      return try await existing.value
    }

    let task = Task<URL, Error> { [contentStore] in
      defer { inFlightDownloads[key] = nil }

      let request = try request(
        .download(documentId: document.id, original: original, version: version))
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
    documentID: UInt, original: Bool, version: UInt?,
    progress: (@Sendable (Double) -> Void)?
  ) async throws -> URL {
    let request = try request(
      .download(documentId: documentID, original: original, version: version))
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
    try await get(ApiCorrespondent.self, endpoint: .correspondent(id: id))?.domain
  }

  public func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
    let api: ApiCorrespondent = try await create(
      element: ApiCorrespondentCreate(from: correspondent),
      endpoint: .createCorrespondent(),
      returns: ApiCorrespondent.self)
    return api.domain
  }

  public func update(correspondent: Correspondent) async throws -> Correspondent {
    let api: ApiCorrespondent = try await update(
      element: ApiCorrespondentUpdate(from: correspondent),
      endpoint: .correspondent(id: correspondent.id),
      returns: ApiCorrespondent.self)
    return api.domain
  }

  public func delete(correspondent: Correspondent) async throws {
    try await delete(Correspondent.self, endpoint: .correspondent(id: correspondent.id))
  }

  public func correspondents() async throws -> [Correspondent] {
    let cursor = try PageCursor<ApiCorrespondent>(
      repository: self,
      initialURL: url(.correspondents()))
    return try await cursor.collectAll().map(\.domain)
  }

  public func documentType(id: UInt) async throws -> DocumentType? {
    try await get(ApiDocumentType.self, endpoint: .documentType(id: id))?.domain
  }

  public func create(documentType: ProtoDocumentType) async throws -> DocumentType {
    let api: ApiDocumentType = try await create(
      element: ApiDocumentTypeCreate(from: documentType),
      endpoint: .createDocumentType(),
      returns: ApiDocumentType.self)
    return api.domain
  }

  public func update(documentType: DocumentType) async throws -> DocumentType {
    let api: ApiDocumentType = try await update(
      element: ApiDocumentTypeUpdate(from: documentType),
      endpoint: .documentType(id: documentType.id),
      returns: ApiDocumentType.self)
    return api.domain
  }

  public func delete(documentType: DocumentType) async throws {
    try await delete(DocumentType.self, endpoint: .documentType(id: documentType.id))
  }

  public func documentTypes() async throws -> [DocumentType] {
    let cursor = try PageCursor<ApiDocumentType>(
      repository: self,
      initialURL: url(.documentTypes()))
    return try await cursor.collectAll().map(\.domain)
  }

  public func document(id: UInt) async throws -> Document? {
    try await get(ApiDocument.self, endpoint: .document(id: id))?.domain
  }

  public func document(asn: UInt) async throws -> Document? {
    Logger.networking.notice("Getting document by ASN")

    let rule = FilterRule(ruleType: .asn, value: .number(value: Int(asn)))!
    let decoded = try await send(
      endpoint: .documents(page: 1, rules: [rule]),
      returns: ListResponse<ApiDocument>.self)

    guard decoded.count > 0, !decoded.results.isEmpty else {
      Logger.networking.notice("Got empty document result (ASN not found)")
      return nil
    }
    return decoded.results.first?.domain
  }

  public func metadata(documentId: UInt) async throws -> Metadata {
    try await send(endpoint: .metadata(documentId: documentId), returns: ApiMetadata.self).domain
  }

  public func notes(documentId: UInt) async throws -> [Document.Note] {
    try await send(endpoint: .notes(documentId: documentId), returns: [ApiDocumentNote].self)
      .map(\.domain)
  }

  public func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note]
  {
    try await send(
      .post,
      endpoint: .notes(documentId: documentId),
      body: ApiDocumentNoteCreate(from: note),
      returns: [ApiDocumentNote].self
    ).map(\.domain)
  }

  public func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
    try await send(
      .delete,
      endpoint: .note(documentId: documentId, noteId: id),
      returns: [ApiDocumentNote].self
    ).map(\.domain)
  }

  public func trash() async throws -> [Document] {
    Logger.networking.notice("Getting trash documents")
    let endpoint = Endpoint.trash(page: 1, pageSize: 100_000)
    let cursor = try PageCursor<ApiDocument>(repository: self, initialURL: url(endpoint))
    return try await cursor.collectAll().map(\.domain)
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
      returns: ListResponse<ApiDocument>.self)
    return (decoded.results.first?.archive_serial_number ?? 0) + 1
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

  public func users() async throws -> [User] {
    let cursor = try PageCursor<ApiUser>(
      repository: self,
      initialURL: url(.users()))
    return try await cursor.collectAll().map(\.domain)
  }

  public func groups() async throws -> [UserGroup] {
    let cursor = try PageCursor<ApiUserGroup>(
      repository: self,
      initialURL: url(.groups()))
    return try await cursor.collectAll().map(\.domain)
  }

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
    let url = try url(
      Endpoint.thumbnail(documentId: document.id, version: document.currentVersionID))

    var request = URLRequest(url: url)
    addTokenTo(request: &request)
    connection.extraHeaders.apply(toRequest: &request)

    return request
  }

  public func suggestions(documentId: UInt) async throws -> Suggestions {
    Logger.networking.notice("Get suggestions")
    return try await send(
      endpoint: .suggestions(documentId: documentId), returns: ApiSuggestions.self
    ).domain
  }

  // MARK: Saved views

  public func savedViews() async throws -> [SavedView] {
    let cursor = try PageCursor<ApiSavedView>(
      repository: self,
      initialURL: url(.savedViews()))
    return try await cursor.collectAll().map(\.domain)
  }

  public func create(savedView view: ProtoSavedView) async throws -> SavedView {
    let api: ApiSavedView = try await create(
      element: ApiSavedViewCreate(from: view),
      endpoint: .createSavedView(),
      returns: ApiSavedView.self)
    return api.domain
  }

  public func update(savedView view: SavedView) async throws -> SavedView {
    let api: ApiSavedView = try await update(
      element: ApiSavedViewUpdate(from: view),
      endpoint: .savedView(id: view.id),
      returns: ApiSavedView.self)
    return api.domain
  }

  public func delete(savedView view: SavedView) async throws {
    try await delete(SavedView.self, endpoint: .savedView(id: view.id))
  }

  // MARK: Storage paths

  public func storagePaths() async throws -> [StoragePath] {
    let cursor = try PageCursor<ApiStoragePath>(
      repository: self,
      initialURL: url(.storagePaths()))
    return try await cursor.collectAll().map(\.domain)
  }

  public func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
    let api: ApiStoragePath = try await create(
      element: ApiStoragePathCreate(from: storagePath),
      endpoint: .createStoragePath(),
      returns: ApiStoragePath.self)
    return api.domain
  }

  public func update(storagePath: StoragePath) async throws -> StoragePath {
    let api: ApiStoragePath = try await update(
      element: ApiStoragePathUpdate(from: storagePath),
      endpoint: .storagePath(id: storagePath.id),
      returns: ApiStoragePath.self)
    return api.domain
  }

  public func delete(storagePath: StoragePath) async throws {
    try await delete(StoragePath.self, endpoint: .storagePath(id: storagePath.id))
  }

  // MARK: Custom fields

  public func customFields() async throws -> [CustomField] {
    let cursor = try PageCursor<ApiCustomField>(
      repository: self,
      initialURL: url(.customFields()))
    return try await cursor.collectAll().map(\.domain)
  }

  // MARK: Server configuration

  public func serverConfiguration() async throws -> ServerConfiguration {
    let configurations = try await send(
      endpoint: .appConfiguration(), returns: [ApiServerConfiguration].self)

    guard let firstConfig = configurations.first else {
      Logger.networking.error("No server configuration found")
      throw RequestError.invalidResponse
    }

    return firstConfig.domain
  }

  public func remoteVersion() async throws -> RemoteVersion {
    try await send(endpoint: .remoteVersion(), returns: ApiRemoteVersion.self).domain
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

  public func tasks() throws -> AnyTaskSource {
    if supports(feature: .taskListEnvelope) {
      let initial = try url(.tasks(name: .consumeFile, acknowledged: false, pageSize: 100))
      let cursor = PageCursor<ApiTaskV10>(repository: self, initialURL: initial)
      return AnyTaskSource(
        ApiPagedSource<ApiTaskV10, PaperlessTask>(cursor: cursor, map: { $0.domain }))
    } else {
      return AnyTaskSource(ApiTaskSourceV9(repository: self))
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

  // Fallback for when we can't read X-Api-Version off the canonical probe.
  // Tries GET /api/ui_settings/ with Accept: application/json; version=N, counting down from max to min,
  // stopping when the backend stops returning 406 (any other status = accepted).
  // Mirrors but isn't shared with LoginViewModel's pre-auth probe.
  private static func iterateAcceptedApiVersion(
    urlSession: URLSession, connection: Connection
  ) async -> UInt? {
    guard let url = Endpoint.uiSettings().url(url: connection.url) else {
      return nil
    }

    Logger.networking.info(
      "Header probe failed; iterating API versions to find one the backend accepts")

    for v in stride(
      from: Int(maximumApiVersion), through: Int(minimumApiVersion), by: -1)
    {
      var request = URLRequest(url: url)
      request.cachePolicy = .reloadIgnoringLocalCacheData
      addTokenTo(request: &request, token: connection.token)
      connection.extraHeaders.apply(toRequest: &request)
      request.setValue(
        "application/json; version=\(v)", forHTTPHeaderField: "Accept")

      do {
        let (_, response) = try await urlSession.getData(for: request)
        guard let response = response as? HTTPURLResponse else { continue }
        if response.statusCode != 406 {
          return UInt(v)
        }
      } catch {
        Logger.networking.warning(
          "Iteration probe network error at version \(v): \(String(describing: error))")
        // Network errors mean we can't tell whether this version was
        // accepted; bail out rather than continue iterating with the same
        // doomed connection.
        return nil
      }
    }

    Logger.networking.error(
      "Iteration probe: backend rejected every API version in [\(minimumApiVersion), \(maximumApiVersion)]"
    )
    return nil
  }

  public func supports(feature: BackendFeature) -> Bool {
    guard let backendVersion, let apiVersion else { return false }
    return feature.isSupported(on: backendVersion, api: apiVersion)
  }

  // MARK: - Share links

  public func shareLinks(documentId: UInt) async throws -> [DataModel.ShareLink] {
    try await send(
      endpoint: .shareLinks(documentId: documentId),
      returns: [ApiShareLink].self
    ).map(\.domain)
  }

  public func create(shareLink: ProtoShareLink) async throws -> DataModel.ShareLink {
    let api: ApiShareLink = try await create(
      element: ApiShareLinkCreate(from: shareLink),
      endpoint: .createShareLink(),
      returns: ApiShareLink.self)
    return api.domain
  }

  public func delete(shareLink: DataModel.ShareLink) async throws {
    try await delete(ShareLink.self, endpoint: .shareLink(id: shareLink.id))
  }
}
