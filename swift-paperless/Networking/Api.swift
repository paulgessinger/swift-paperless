//
//  Api.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import os
import Semaphore
import SwiftUI
import UIKit

enum CrudOperation: String {
    case create
    case read
    case update
    case delete
}

private enum RequestError: Error {
    case invalidRequest
    case invalidResponse
    case unexpectedStatusCode(code: Int)
}

class ApiSequence<Element>: AsyncSequence, AsyncIteratorProtocol where Element: Decodable {
    private var nextPage: URL?
    private let repository: ApiRepository

    private var buffer: [Element]?
    private var bufferIndex = 0

    private(set) var hasMore = true

    private let semaphore = AsyncSemaphore(value: 1)

    init(repository: ApiRepository, url: URL) {
        self.repository = repository
        nextPage = url
    }

    private func fixUrl(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("Unable to decompose next-page URL for sequence URL fix, continuing with original URL")
            return url
        }

        components.scheme = repository.connection.scheme

        guard let result = components.url else {
            Logger.api.error("Could not reassemble URL after sequence URL fix, continuing with original URL")
            return url
        }

        return result
    }

    func next() async throws -> Element? {
        await semaphore.wait()
        defer { semaphore.signal() }

        guard !Task.isCancelled else {
            Logger.api.notice("API sequence next task was cancelled.")
            return nil
        }

        // if we have a current page loaded, return next element from that
        if let buffer, bufferIndex < buffer.count {
            defer { bufferIndex += 1 }
            return buffer[bufferIndex]
        }

        guard let url = nextPage else {
            Logger.api.notice("API sequence has reached end (nextPage is nil)")
            hasMore = false
            return nil
        }

        do {
            let request = repository.request(url: url)
            let decoded = try await repository.fetchData(for: request, as: ListResponse<Element>.self)

            guard !decoded.results.isEmpty else {
                Logger.api.notice("API sequence fetch was empty")
                hasMore = false
                return nil
            }

            // Workaround for https://github.com/paulgessinger/swift-paperless/issues/68
            Logger.api.trace("Fixing URL to next page with configured backend scheme")

            nextPage = nil
            if let next = decoded.next {
                nextPage = fixUrl(next)
            }
            buffer = decoded.results
            bufferIndex = 1 // set to one because we return the first element immediately
            return decoded.results[0]

        } catch {
            Logger.api.error("Error in API sequence: \(error)")
            throw error
        }
    }

    func makeAsyncIterator() -> ApiSequence {
        self
    }
}

class ApiDocumentSource: DocumentSource {
    typealias DocumentSequence = ApiSequence<Document>

    var sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    func fetch(limit: UInt) async throws -> [Document] {
        guard sequence.hasMore else {
            return []
        }
        return try await Array(sequence.prefix(Int(limit)))
    }

    func hasMore() async -> Bool { sequence.hasMore }
}

class ApiRepository {
    let connection: Connection

    private var apiVersion: UInt?
    private var backendVersion: (UInt, UInt, UInt)?

    init(connection: Connection) {
        self.connection = connection
        Logger.api.notice("Initializing ApiRepository with connection \(connection.url, privacy: .private) \(connection.token, privacy: .private)")

        Task {
            await ensureBackendVersions()

            if let apiVersion, let backendVersion {
                Logger.api.notice("Backend version info: API version: \(apiVersion), backend version: \(backendVersion.0).\(backendVersion.1).\(backendVersion.2)")
            } else {
                Logger.api.warning("Did not get backend version info")
            }
        }
    }

    private var apiToken: String {
        connection.token
    }

    func url(_ endpoint: Endpoint) -> URL {
        let connection = connection
        Logger.api.trace("Making API endpoint URL with \(connection.url) for \(endpoint.path)")
        return endpoint.url(url: connection.url)!
    }

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    fileprivate func request(url: URL) -> URLRequest {
        let sanitizedUrl = sanitizeUrlForLog(url)
        Logger.api.trace("Creating API request for URL \(sanitizedUrl, privacy: .public)")
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; version=3", forHTTPHeaderField: "Accept")
        connection.extraHeaders.apply(toRequest: &request)
        return request
    }

    fileprivate func request(_ endpoint: Endpoint) -> URLRequest {
        request(url: url(endpoint))
    }

    private func sanitizeUrlForLog(_ url: URL) -> String {
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
    }

    fileprivate func fetchData(for request: URLRequest, code: Int = 200) async throws -> (Data, URLResponse) {
        guard let url = request.url else {
            Logger.api.error("Request URL is nil")
            throw RequestError.invalidRequest
        }

        let sanitizedUrl = sanitizeUrlForLog(url)
        Logger.api.trace("Fetching request data for \(sanitizedUrl, privacy: .public)")

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            Logger.api.error("Caught error fetching \(sanitizedUrl, privacy: .public): \(error)")
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
            throw RequestError.unexpectedStatusCode(code: response.statusCode)
        }

        Logger.api.trace("URLResponse for \(sanitizedUrl, privacy: .public) has status code \(code) as expected")

        return (data, response)
    }

    fileprivate func fetchData<T: Decodable>(for request: URLRequest, as type: T.Type, code: Int = 200) async throws -> T {
        let (data, _) = try await fetchData(for: request, code: code)
        do {
            return try decoder.decode(type, from: data)
        } catch let error as DecodingError {
            let url = request.url!
            let body = String(data: data, encoding: .utf8) ?? "[NO BODY]"
            Logger.api.error("Unable to decode response to \(self.sanitizeUrlForLog(url), privacy: .public) as \(T.self) from body \(body, privacy: .public): \(error)")
            throw error
        }
    }

    private func get<T: Decodable & Model>(_ type: T.Type, id: UInt) async -> T? {
        let request = request(.single(T.self, id: id))

        do {
            return try await fetchData(for: request, as: type)
        } catch {
            Logger.api.error("Error getting \(type) with id \(id): \(error)")
            return nil
        }
    }

    private func all<T: Decodable & Model>(_: T.Type) async throws -> [T] {
        let sequence = ApiSequence<T>(repository: self,
                                      url: url(.listAll(T.self)))
        return try await Array(sequence)
    }

    private func create<Element>(element: some Encodable, endpoint: Endpoint, returns: Element.Type) async throws -> Element where Element: Decodable {
        var request = request(endpoint)

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
        var request = request(endpoint)

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
        var request = request(endpoint)
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
        try await update(element: document, endpoint: .document(id: document.id))
    }

    func create(document: ProtoDocument, file: URL) async throws {
        Logger.api.notice("Creating document")
        var request = request(.createDocument())

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

    func documents(filter: FilterState) -> any DocumentSource {
        Logger.api.notice("Getting document sequence for filter")
        return ApiDocumentSource(
            sequence: ApiSequence<Document>(repository: self,
                                            url: url(.documents(page: 1, filter: filter))))
    }

    func download(documentID: UInt) async -> URL? {
        Logger.api.notice("Downloading document")
        let request = request(.download(documentId: documentID))

        do {
            let (data, response) = try await fetchData(for: request, code: 200)

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

    func tag(id: UInt) async -> Tag? { await get(Tag.self, id: id) }

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

    func correspondent(id: UInt) async -> Correspondent? { await get(Correspondent.self, id: id) }

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

    func documentType(id: UInt) async -> DocumentType? { await get(DocumentType.self, id: id) }

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

    func document(id: UInt) async -> Document? { await get(Document.self, id: id) }

    func document(asn: UInt) async -> Document? {
        Logger.api.notice("Getting document by ASN")
        let endpoint = Endpoint.documents(page: 1, rules: [FilterRule(ruleType: .asn, value: .number(value: Int(asn)))])

        let request = request(endpoint)

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

    private func nextAsnCompatibility() async -> UInt {
        Logger.api.notice("Getting next ASN with legacy compatibility method")
        var fs = FilterState()
        fs.sortField = .asn
        fs.sortOrder = .descending
        let endpoint = Endpoint.documents(page: 1, filter: fs, pageSize: 1)
        let url = url(endpoint)
        Logger.api.notice("\(url)")

        let request = request(endpoint)

        do {
            let decoded = try await fetchData(for: request, as: ListResponse<Document>.self)

            return (decoded.results.first?.asn ?? 0) + 1
        } catch {
            Logger.api.error("Error fetching document for next ASN: \(error)")
        }

        return 0
    }

    private func nextAsnDirectEndpoint() async -> UInt {
        Logger.api.notice("Getting next ASN with dedicated endpoint")
        let request = request(.nextAsn())

        do {
            let asn = try await fetchData(for: request, as: UInt.self)
            Logger.api.notice("Have next ASN \(asn)")
            return asn
        } catch {
            Logger.api.error("Error fetching next ASN: \(error)")
            return 0
        }
    }

    func nextAsn() async -> UInt {
        if apiVersion == nil || backendVersion == nil {
            await ensureBackendVersions()
        }

        if let backendVersion, backendVersion >= (2, 0, 0) {
            return await nextAsnDirectEndpoint()
        } else {
            return await nextAsnCompatibility()
        }
    }

    func users() async throws -> [User] { try await all(User.self) }

    func thumbnail(document: Document) async -> Image? {
        guard let data = await thumbnailData(document: document) else {
            Logger.api.error("Did not get thumbnail data")
            return nil
        }
        guard let uiImage = UIImage(data: data) else {
            Logger.api.error("Thumbnail data did not decode as image")
            return nil
        }
        let image = Image(uiImage: uiImage)
        return image
    }

    func thumbnailData(document: Document) async -> Data? {
        Logger.api.notice("Get thumbnail")
        let url = url(Endpoint.thumbnail(documentId: document.id))

        // @TODO: Can this be a regular request?
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        connection.extraHeaders.apply(toRequest: &request)

        do {
            let (data, _) = try await fetchData(for: request)
            return data
        } catch {
            Logger.api.error("Error getting thumbnail data for document: \(error)")
            return nil
        }
    }

    func suggestions(documentId: UInt) async -> Suggestions {
        Logger.api.notice("Get suggestions")
        let request = request(.suggestions(documentId: documentId))

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
        let request = request(.uiSettings())
        let (data, _) = try await fetchData(for: request)
        let uiSettings = try decoder.decode(UiSettingsResponse.self, from: data)
        return uiSettings.user
    }

    func tasks() async -> [PaperlessTask] {
        let request = request(.tasks())

        do {
            return try await fetchData(for: request, as: [PaperlessTask].self)
        } catch {
            Logger.api.error("Unable to load tasks: \(error)")
            return []
        }
    }

    private func ensureBackendVersions() async {
        Logger.api.notice("Getting backend versions")
        let request = request(.root())
        do {
            let (_, res) = try await fetchData(for: request)

            // fetchData should have already ensured this
            guard let res = res as? HTTPURLResponse else {
                Logger.api.error("Unable to get API and backend version: Not an HTTP response")
                return
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
