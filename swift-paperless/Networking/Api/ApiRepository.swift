//
//  ApiRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import AsyncAlgorithms
import Foundation
import os
import Semaphore
import SwiftUI
import UIKit

actor ApiDocumentSource: DocumentSource {
    typealias DocumentSequence = ApiSequence<Document>

    private let sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    func fetch(limit: UInt) async throws -> [Document] {
        guard await sequence.hasMore else {
            return []
        }
        return try await Array(sequence.prefix(Int(limit)))
    }

    func hasMore() async -> Bool { await sequence.hasMore }
}

actor ApiRepository {
    nonisolated
    let connection: Connection

    private let urlSession: URLSession
    private let urlSessionDelegate: PaperlessURLSessionDelegate

    private var apiVersion: UInt?
    private var minimumApiVersion: UInt = 3
    private var maximumApiVersion: UInt = 5
    private var backendVersion: (UInt, UInt, UInt)?

    private var effectiveApiVersion: UInt {
        min(maximumApiVersion, max(minimumApiVersion, apiVersion ?? minimumApiVersion))
    }

    init(connection: Connection) async {
        self.connection = connection
        let sanitizedUrl = Self.sanitizeUrlForLog(connection.url)
        let tokenStr = connection.token != nil ? "<token len: \(connection.token?.count ?? 0)>" : "nil"
        Logger.api.notice("Initializing ApiRepository with connection \(sanitizedUrl, privacy: .public) and token \(tokenStr, privacy: .public)")

        let delegate = PaperlessURLSessionDelegate(identityName: connection.identity)

        urlSessionDelegate = delegate
        urlSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        await loadBackendVersions()

        if let apiVersion, let backendVersion {
            Logger.api.notice("Backend version info: API version: \(apiVersion), backend version: \(backendVersion.0).\(backendVersion.1).\(backendVersion.2)")

            if apiVersion < minimumApiVersion || maximumApiVersion < apiVersion {
                let minimumApiVersion = minimumApiVersion
                let maximumApiVersion = maximumApiVersion
                Logger.api.info("Backend API version \(apiVersion) is outside of tested range of API versions [\(minimumApiVersion), \(maximumApiVersion)]")
            }

        } else {
            Logger.api.warning("Did not get backend version info")
        }
    }

    nonisolated
    var delegate: (any URLSessionDelegate)? {
        urlSessionDelegate
    }

    private nonisolated
    var apiToken: String? {
        connection.token
    }

    nonisolated
    func url(_ endpoint: Endpoint) throws -> URL {
        let connection = connection
        Logger.api.trace("Making API endpoint URL with \(connection.url) for \(endpoint.path)")
        guard let url = endpoint.url(url: connection.url) else {
            let sanitizedUrl = Self.sanitizeUrlForLog(connection.url)
            Logger.api.error("Unable to make URL: \(sanitizedUrl, privacy: .public)")
            throw RequestError.invalidRequest
        }
        return url
    }

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func request(url: URL) -> URLRequest {
        let sanitizedUrl = Self.sanitizeUrlForLog(url)
        var request = URLRequest(url: url)
        if let apiToken {
            request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json; version=\(effectiveApiVersion)", forHTTPHeaderField: "Accept")
        connection.extraHeaders.apply(toRequest: &request)
        Logger.api.trace("Creating API request for URL \(sanitizedUrl, privacy: .public), headers: \(request.allHTTPHeaderFields ?? [:])")
        return request
    }

    func request(_ endpoint: Endpoint) throws -> URLRequest {
        try request(url: url(endpoint))
    }

    private nonisolated
    static func sanitizeUrlForLog(_ url: URL) -> String {
        #if DEBUG
            return url.absoluteString
        #else
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                Logger.api.error("sanitizeUrlForLog failed")
                return "<private>"
            }

            components.host = "example.com"
            guard let result = components.url else {
                Logger.api.error("sanitizeUrlForLog failed")
                return "<private>"
            }

            return result.absoluteString
        #endif
    }

    func sanitizedError(_ error: some Error) -> String {
        #if DEBUG
            return String(describing: error)
        #else
            return String(describing: error).replacingOccurrences(of: connection.url.absoluteString, with: "\(connection.scheme)://example.com")
        #endif
    }

    private func decodeDetails(_ data: Data) -> String {
        struct Details: Decodable {
            var detail: String
        }

        do {
            let details = try decoder.decode(Details.self, from: data)
            return details.detail
        } catch {
            return String(data: data, encoding: .utf8) ?? "[NO BODY]"
        }
    }

    private func fetchData(for request: URLRequest, code: Int = 200,
                           progress: (@Sendable (Double) -> Void)? = nil) async throws -> (Data, URLResponse)
    {
        guard let url = request.url else {
            Logger.api.error("Request URL is nil")
            throw RequestError.invalidRequest
        }

        let sanitizedUrl = Self.sanitizeUrlForLog(url)
        Logger.api.trace("Fetching request data for \(request.httpMethod ?? "??", privacy: .public) \(sanitizedUrl, privacy: .public)")

        let result: (Data, URLResponse)
        do {
            result = try await urlSession.getData(for: request, progress: progress)
        } catch let error as CancellationError {
            Logger.api.trace("Fetch request task was cancelled")
            throw error
        } catch {
            let sanitizedError = sanitizedError(error)
            Logger.api.error("Caught error fetching \(sanitizedUrl, privacy: .public): \(sanitizedError, privacy: .public)")
            throw error
        }

        let (data, response) = result

        Logger.api.trace("Checking response of url \(sanitizedUrl, privacy: .public)")

        guard let response = response as? HTTPURLResponse else {
            let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
            Logger.api.error("Response to \(sanitizedUrl, privacy: .public) is not HTTPURLResponse, body: \(body, privacy: .public)")
            throw RequestError.invalidResponse
        }

        if response.statusCode != code {
            let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
            Logger.api.error("URLResponse to \(sanitizedUrl, privacy: .public) has status code \(response.statusCode) != \(code), body: \(body, privacy: .public)")
            if response.statusCode == 403 {
                throw RequestError.forbidden(detail: decodeDetails(data))
            } else if response.statusCode == 401 {
                throw RequestError.unauthorized(detail: decodeDetails(data))
            } else {
                throw RequestError.unexpectedStatusCode(code: response.statusCode)
            }
        }

        Logger.api.trace("URLResponse for \(sanitizedUrl, privacy: .public) has status code \(code) as expected")

        return (data, response)
    }

    func fetchData<T: Decodable>(for request: URLRequest, as type: T.Type, code: Int = 200) async throws -> T {
        let (data, _) = try await fetchData(for: request, code: code)
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            let url = request.url!
            let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
            if Bundle.main.appConfiguration == .AppStore {
                Logger.api.error("Unable to decode response to \(Self.sanitizeUrlForLog(url), privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .private): \(error)")
            } else {
                Logger.api.error("Unable to decode response to \(Self.sanitizeUrlForLog(url), privacy: .public) as \(T.self, privacy: .public) from body \(body, privacy: .public): \(error)")
            }
            throw error
        }
    }

    private func get<T: Decodable & Model>(_ type: T.Type, id: UInt) async throws -> T? {
        let request = try request(.single(T.self, id: id))

        do {
            return try await fetchData(for: request, as: type)
        } catch {
            Logger.api.error("Error getting \(type, privacy: .public) with id \(id, privacy: .public): \(error)")
            return nil
        }
    }

    private func all<T: Decodable & Model & Sendable>(_: T.Type) async throws -> [T] {
        let sequence = try ApiSequence<T>(repository: self,
                                          url: url(.listAll(T.self)))
        return try await Array(sequence)
    }

    private func create<Element>(element: some Encodable, endpoint: Endpoint, returns: Element.Type) async throws -> Element where Element: Decodable {
        var request = try request(endpoint)

        let body = try JSONEncoder().encode(element)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, _) = try await fetchData(for: request, code: 201)

            let created = try decoder.decode(returns, from: data)
            return created
        } catch {
            Logger.api.error("Api create \(returns) failed: \(error)")
            throw error
        }
    }

    private func update<Element>(element: Element, endpoint: Endpoint) async throws -> Element where Element: Codable {
        var request = try request(endpoint)

        let body = try encoder.encode(element)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            return try await fetchData(for: request, as: Element.self)
        } catch {
            Logger.api.error("Api update \(Element.self) failed: \(error)")
            throw error
        }
    }

    private func delete<Element>(element _: Element, endpoint: Endpoint) async throws {
        var request = try request(endpoint)
        request.httpMethod = "DELETE"

        do {
            _ = try await fetchData(for: request, code: 204)
        } catch {
            Logger.api.error("Api delete \(Element.self) failed: \(error)")
            throw error
        }
    }
}

extension ApiRepository: Repository {
    func update(document: Document) async throws -> Document {
        try await update(element: document,
                         endpoint: .document(id: document.id, fullPerms: false))
    }

    func create(document: ProtoDocument, file: URL) async throws {
        Logger.api.notice("Creating document")
        var request = try request(.createDocument())

        let mp = MultiPartFormDataRequest()
        mp.add(name: "title", string: document.title)

        if let corr = document.correspondent {
            mp.add(name: "correspondent", string: String(corr))
        }

        if let dt = document.documentType {
            mp.add(name: "document_type", string: String(dt))
        }

        for tag in document.tags {
            mp.add(name: "tags", string: String(tag))
        }

        try mp.add(name: "document", url: file)
        mp.addTo(request: &request)

        do {
            let _ = try await fetchData(for: request, code: 200)
        } catch let RequestError.unexpectedStatusCode(code) where code == 413 {
            throw DocumentCreateError.tooLarge
        } catch {
            Logger.api.error("Error uploading document: \(error)")
            throw error
        }
    }

    func delete(document: Document) async throws {
        Logger.api.notice("Deleting document")
        try await delete(element: document, endpoint: .document(id: document.id))
    }

    func documents(filter: FilterState) throws -> any DocumentSource {
        Logger.api.notice("Getting document sequence for filter")
        return try ApiDocumentSource(
            sequence: ApiSequence<Document>(repository: self,
                                            url: url(.documents(page: 1, filter: filter))))
    }

    func download(documentID: UInt, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL? {
        Logger.api.notice("Downloading document")
        do {
            let request = try request(.download(documentId: documentID))

            let (data, response) = try await fetchData(for: request, code: 200,
                                                       progress: progress)

            guard let suggestedFilename = response.suggestedFilename else {
                Logger.api.error("Cannot get suggested filename from response")
                return nil
            }

            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(suggestedFilename)

            try data.write(to: temporaryFileURL, options: .atomic)
            try await Task.sleep(for: .seconds(0.2)) // wait a little bit for the data to be flushed
            return temporaryFileURL

        } catch {
            Logger.api.error("Error downloading document: \(error)")
            return nil
        }
    }

    func tag(id: UInt) async throws -> Tag? { try await get(Tag.self, id: id) }

    func create(tag: ProtoTag) async throws -> Tag {
        try await create(element: tag, endpoint: .createTag(), returns: Tag.self)
    }

    func update(tag: Tag) async throws -> Tag {
        try await update(element: tag, endpoint: .tag(id: tag.id))
    }

    func delete(tag: Tag) async throws {
        try await delete(element: tag, endpoint: .tag(id: tag.id))
    }

    func tags() async throws -> [Tag] { try await all(Tag.self) }

    func correspondent(id: UInt) async throws -> Correspondent? { try await get(Correspondent.self, id: id) }

    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
        try await create(element: correspondent,
                         endpoint: .createCorrespondent(),
                         returns: Correspondent.self)
    }

    func update(correspondent: Correspondent) async throws -> Correspondent {
        try await update(element: correspondent,
                         endpoint: .correspondent(id: correspondent.id))
    }

    func delete(correspondent: Correspondent) async throws {
        try await delete(element: correspondent,
                         endpoint: .correspondent(id: correspondent.id))
    }

    func correspondents() async throws -> [Correspondent] { try await all(Correspondent.self) }

    func documentType(id: UInt) async throws -> DocumentType? { try await get(DocumentType.self, id: id) }

    func create(documentType: ProtoDocumentType) async throws -> DocumentType {
        try await create(element: documentType,
                         endpoint: .createDocumentType(),
                         returns: DocumentType.self)
    }

    func update(documentType: DocumentType) async throws -> DocumentType {
        try await update(element: documentType,
                         endpoint: .documentType(id: documentType.id))
    }

    func delete(documentType: DocumentType) async throws {
        try await delete(element: documentType,
                         endpoint: .documentType(id: documentType.id))
    }

    func documentTypes() async throws -> [DocumentType] { try await all(DocumentType.self) }

    func document(id: UInt) async throws -> Document? { try await get(Document.self, id: id) }

    func document(asn: UInt) async throws -> Document? {
        Logger.api.notice("Getting document by ASN")
        let endpoint = Endpoint.documents(page: 1, rules: [FilterRule(ruleType: .asn, value: .number(value: Int(asn)))])

        let request = try request(endpoint)

        do {
            let decoded = try await fetchData(for: request, as: ListResponse<Document>.self)

            guard decoded.count > 0, !decoded.results.isEmpty else {
                // this means the ASN was not found
                Logger.api.notice("Got empty document result (ASN not found)")
                return nil
            }
            return decoded.results.first

        } catch {
            Logger.api.error("Error fetching document by ASN \(asn): \(error)")
            return nil
        }
    }

    func metadata(documentId: UInt) async throws -> Metadata {
        let request = try request(.metadata(documentId: documentId))
        do {
            let decoded = try await fetchData(for: request, as: Metadata.self)
            return decoded
        } catch {
            Logger.api.error("Error fetching document metadata for id \(documentId): \(error)")
            throw error
        }
    }

    func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note] {
        var request = try request(.notes(documentId: documentId))
        let body = try JSONEncoder().encode(note)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            return try await fetchData(for: request, as: [Document.Note].self, code: 200)
        } catch {
            Logger.shared.error("Error creating note on document \(documentId): \(error)")
            throw error
        }
    }

    func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
        var request = try request(.note(documentId: documentId, noteId: id))
        request.httpMethod = "DELETE"

        do {
            return try await fetchData(for: request, as: [Document.Note].self, code: 200)
        } catch {
            Logger.shared.error("Error deleting note on document \(documentId): \(error)")
            throw error
        }
    }

    private func nextAsnCompatibility() async throws -> UInt {
        Logger.api.notice("Getting next ASN with legacy compatibility method")
        var fs = FilterState()
        fs.sortField = .asn
        fs.sortOrder = .descending
        let endpoint = Endpoint.documents(page: 1, filter: fs, pageSize: 1)
        let url = try url(endpoint)
        Logger.api.notice("\(url)")

        let request = try request(endpoint)

        do {
            let decoded = try await fetchData(for: request, as: ListResponse<Document>.self)

            return (decoded.results.first?.asn ?? 0) + 1
        } catch {
            Logger.api.error("Error fetching document for next ASN: \(error)")
        }

        return 0
    }

    private func nextAsnDirectEndpoint() async throws -> UInt {
        Logger.api.notice("Getting next ASN with dedicated endpoint")
        let request = try request(.nextAsn())

        do {
            let asn = try await fetchData(for: request, as: UInt.self)
            Logger.api.notice("Have next ASN \(asn)")
            return asn
        } catch {
            Logger.api.error("Error fetching next ASN: \(error)")
            return 0
        }
    }

    func nextAsn() async throws -> UInt {
        if let backendVersion, backendVersion >= (2, 0, 0) {
            try await nextAsnDirectEndpoint()
        } else {
            try await nextAsnCompatibility()
        }
    }

    func users() async throws -> [User] { try await all(User.self) }

    func groups() async throws -> [UserGroup] { try await all(UserGroup.self) }

    func thumbnail(document: Document) async throws -> Image? {
        let data = try await thumbnailData(document: document)
        guard let uiImage = UIImage(data: data) else {
            Logger.api.error("Thumbnail data did not decode as image")
            return nil
        }
        let image = Image(uiImage: uiImage)
        return image
    }

    func thumbnailData(document: Document) async throws -> Data {
        let request = try thumbnailRequest(document: document)
        do {
            let (data, _) = try await fetchData(for: request)
            return data
        } catch is CancellationError {
            Logger.api.trace("Thumbnail data request task was cancelled")
            throw CancellationError()
        } catch {
            Logger.api.error("Error getting thumbnail data for document \(document.id, privacy: .public): \(error)")
            throw error
        }
    }

    nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest {
        Logger.api.notice("Get thumbnail for document \(document.id, privacy: .public)")
        let url = try url(Endpoint.thumbnail(documentId: document.id))

        var request = URLRequest(url: url)
        if let apiToken {
            request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        }
        connection.extraHeaders.apply(toRequest: &request)

        return request
    }

    func suggestions(documentId: UInt) async throws -> Suggestions {
        Logger.api.notice("Get suggestions")
        let request = try request(.suggestions(documentId: documentId))

        do {
            return try await fetchData(for: request, as: Suggestions.self)
        } catch {
            Logger.api.error("Unable to load suggestions: \(error)")
            return .init()
        }
    }

    // MARK: Saved views

    func savedViews() async throws -> [SavedView] {
        try await all(SavedView.self)
    }

    func create(savedView view: ProtoSavedView) async throws -> SavedView {
        try await create(element: view, endpoint: .createSavedView(), returns: SavedView.self)
    }

    func update(savedView view: SavedView) async throws -> SavedView {
        try await update(element: view, endpoint: .savedView(id: view.id))
    }

    func delete(savedView view: SavedView) async throws {
        try await delete(element: view, endpoint: .savedView(id: view.id))
    }

    // MARK: Storage paths

    func storagePaths() async throws -> [StoragePath] {
        try await all(StoragePath.self)
    }

    func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
        try await create(element: storagePath, endpoint: .createStoragePath(), returns: StoragePath.self)
    }

    func update(storagePath: StoragePath) async throws -> StoragePath {
        try await update(element: storagePath, endpoint: .savedView(id: storagePath.id))
    }

    func delete(storagePath: StoragePath) async throws {
        try await delete(element: storagePath, endpoint: .storagePath(id: storagePath.id))
    }

    private struct UiSettingsResponse: Codable {
        var user: User
    }

    func currentUser() async throws -> User {
        let request = try request(.uiSettings())
        let (data, _) = try await fetchData(for: request)
        let uiSettings = try decoder.decode(UiSettingsResponse.self, from: data)
        return uiSettings.user
    }

    func tasks() async throws -> [PaperlessTask] {
        let request = try request(.tasks())

        do {
            return try await fetchData(for: request, as: [PaperlessTask].self)
        } catch {
            Logger.api.error("Unable to load tasks: \(error)")
            throw error
        }
    }

    func task(id: UInt) async throws -> PaperlessTask? {
        let request = try request(.task(id: id))

        return try await fetchData(for: request, as: PaperlessTask.self)
    }

    func acknowledge(tasks ids: [UInt]) async throws {
        var request = try request(.acknowlegdeTasks())

        let payload: [String: [UInt]] = ["tasks": ids]

        let body = try JSONEncoder().encode(payload)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            _ = try await fetchData(for: request, code: 200)
        } catch {
            Logger.api.error("Api acknowledge failed: \(error)")
            throw error
        }
    }

    private func loadBackendVersions() async {
        Logger.api.info("Getting backend versions")
        do {
            let request = try request(.root())

            let (_, res) = try await fetchData(for: request)

            // fetchData should have already ensured this
            guard let res = res as? HTTPURLResponse else {
                Logger.api.error("Unable to get API and backend version: Not an HTTP response")
                return
            }

            if res.statusCode != 200 {
                Logger.api.error("Status code for version request was \(res.statusCode), not 200. Usually this means authentication is broken.")
            }

            let backend1 = res.value(forHTTPHeaderField: "X-Version")
            let backend2 = res.value(forHTTPHeaderField: "x-version")

            guard let backend1, let backend2 else {
                Logger.api.error("Unable to get API and backend version: X-Version not found")
                return
            }
            let backend = [backend1, backend2].compactMap { $0 }.first!

            let parts = backend.components(separatedBy: ".").compactMap { UInt($0) }
            guard parts.count == 3 else {
                Logger.api.error("Unable to get API and backend version: Invalid format \(backend)")
                return
            }

            let backendVersion = (parts[0], parts[1], parts[2])

            guard let apiVersion = res.value(forHTTPHeaderField: "X-Api-Version"), let apiVersion = UInt(apiVersion) else {
                Logger.api.error("Unable to get API and backend version: X-Api-Version not found")
                return
            }

            self.apiVersion = apiVersion
            self.backendVersion = backendVersion
        } catch {
            Logger.api.error("Unable to get API and backend version, error: \(error)")
            return
        }
    }
}
