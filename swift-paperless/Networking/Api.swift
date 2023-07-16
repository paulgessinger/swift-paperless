//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import os
import Semaphore
import SwiftUI
import UIKit

let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder -> Date in
        let container = try decoder.singleValueContainer()
        let dateStr = try container.decode(String.self)

        let iso = ISO8601DateFormatter()
        if let res = iso.date(from: dateStr) {
            return res
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSZZZZZ"

        guard let res = df.date(from: dateStr) else {
            throw DateDecodingError.invalidDate(string: dateStr)
        }

        return res
    }
//    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

enum CrudOperation: String {
    case create
    case read
    case update
    case delete
}

struct CrudApiError<Element>: Error, LocalizedError {
    var operation: CrudOperation
    var type: Element.Type
    var status: Int?
    var body: String? = nil

    var errorDescription: String? {
        return "Failed to \(operation.rawValue) \(type)"
    }

    var failureReason: String? {
        return "Backend replied with unexpected status: \(String(describing: status))"
    }
}

// enum CrudApiError<Element>: Error, LocalizedError {
//    case put(type: Element.Type, status: Int, body: String)
//    case delete(type: Element.Type, status: Int, body: String)
//    case post(type: Element.Type, status: Int, body: String)
//    case post(type: Element.Type, status: Int, body: String)
//
//    var operation: String {
//        switch self {
//        case .put:
//            return "update"
//        case .delete:
//            return "delete"
//        case .post:
//            return "create"
//        }
//    }
//
//    var errorDescription: String? {
//        return "Failed to \(operation) object \(Element.self)"
//    }
// }

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

    func xprint(_ s: String) {
        if Element.self == Document.self {
            print(s)
        }
    }

    func next() async -> Element? {
        await semaphore.wait()
        defer { semaphore.signal() }

//        xprint("ENTER next")
        guard !Task.isCancelled else {
            return nil
        }

        // if we have a current page loaded, return next element from that
        if let buffer = buffer, bufferIndex < buffer.count {
//            xprint("Return from buffer")
            defer { bufferIndex += 1 }
            return buffer[bufferIndex]
        }

        guard let url = nextPage else {
//            xprint("No next page")
            hasMore = false
            return nil
        }

        do {
//            xprint("Fetch more")
            let request = repository.request(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)

            let decoded = try decoder.decode(ListResponse<Element>.self, from: data)

            guard !decoded.results.isEmpty else {
//                xprint("Fetch was empty")
                hasMore = false
                return nil
            }

//            if Element.self is Document.Type {
//                print(url)
//                print("Got \(decoded.results.count)")
//            }

//            xprint("Fetch was good, returning")
            nextPage = decoded.next
//            print("next: \(nextPage)")
            buffer = decoded.results
            bufferIndex = 1 // set to one because we return the first element immediately
            return decoded.results[0]

        } catch {
//            xprint("Got error")
            print("ERROR: \(error)")
            return nil
        }
    }

    func makeAsyncIterator() -> ApiSequence {
        return self
    }
}

class ApiDocumentSource: DocumentSource {
    typealias DocumentSequence = ApiSequence<Document>

    var sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    func fetch(limit: UInt) async -> [Document] {
//        print("CALL FETCH")
//        var result = [Document]()
//        for _ in 0 ..< limit {
//            guard let doc = await sequence.next() else {
//                break
//            }
//            result.append(doc)
//        }
//        return result
        return await Array(sequence.prefix(Int(limit)))
    }

    func hasMore() async -> Bool { sequence.hasMore }
}

class ApiRepository {
    private let connection: Connection

    init(connection: Connection) {
        self.connection = connection
        Logger.shared.trace("Initializing ApiRespository with connection \(connection.host, privacy: .private) \(connection.token, privacy: .private)")
    }

    private var apiToken: String {
        connection.token
    }

    func url(_ endpoint: Endpoint) -> URL {
        let connection = self.connection
        Logger.shared.trace("Making API endpoint URL with \(connection.host) for \(endpoint.path)")
        return endpoint.url(host: connection.host)!
    }

    let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
//        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    fileprivate func request(url: URL) -> URLRequest {
        Logger.shared.trace("Creating API request for URL \(url)")
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; version=2", forHTTPHeaderField: "Accept")
        connection.extraHeaders.apply(toRequest: &request)
        return request
    }

    fileprivate func request(_ endpoint: Endpoint) -> URLRequest {
        request(url: url(endpoint))
    }

    private func get<T: Decodable & Model>(_ type: T.Type, id: UInt) async -> T? {
        let request = request(.single(T.self, id: id))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Getting correspondent: Status was not 200")
                return nil
            }

            let correspondent = try decoder.decode(type, from: data)
            return correspondent
        } catch {
            print("Error getting \(type) with id \(id): \(error)")
            return nil
        }
    }

    private func all<T: Decodable & Model>(_ type: T.Type) async -> [T] {
        let sequence = ApiSequence<T>(repository: self,
                                      url: url(.listAll(T.self)))
        return await Array(sequence)
    }

    private func create<ProtoElement, Element>(element: ProtoElement, endpoint: Endpoint, returns: Element.Type) async throws -> Element where ProtoElement: Encodable, Element: Decodable {
        var request = request(endpoint)
//        print("Create: \(request.url!)")

        let body = try JSONEncoder().encode(element)
//        print("Create \(returns): \(String(describing: String(data: body, encoding: .utf8)!))")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 201 {
                let body = String(data: data, encoding: .utf8) ?? "No body"

                throw CrudApiError(operation: .create,
                                   type: returns,
                                   status: hres.statusCode,
                                   body: body)
            }

            let created = try decoder.decode(returns, from: data)
            return created
        } catch {
            print("Error creating \(returns): \(error)")
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
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "No body"

                throw CrudApiError(operation: .update,
                                   type: Element.self,
                                   status: hres.statusCode,
                                   body: body)
            }

            return try decoder.decode(Element.self, from: data)

        } catch {
            print(error)
            throw error
        }
    }

    private func delete<Element>(element: Element, endpoint: Endpoint) async throws {
        var request = request(endpoint)
        request.httpMethod = "DELETE"

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 204 {
                let body = String(data: data, encoding: .utf8) ?? "No body"

                throw CrudApiError(operation: .delete,
                                   type: Element.self,
                                   status: hres.statusCode,
                                   body: body)
            }

        } catch {
            print(error)
            throw error
        }
    }
}

extension ApiRepository: Repository {
    func update(document: Document) async throws -> Document {
        return try await update(element: document, endpoint: .document(id: document.id))
    }

    func create(document: ProtoDocument, file: URL) async throws {
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
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "No body"
                Logger.shared.notice("Create response return code \(hres.statusCode) and body \(body)")
                throw CrudApiError(operation: .create, type: Document.self, status: hres.statusCode)
            }
        } catch {
            print("Error uploading: \(error)")
            throw error
        }
    }

    func delete(document: Document) async throws {
        try await delete(element: document, endpoint: .document(id: document.id))
    }

    func documents(filter: FilterState) -> any DocumentSource {
        return ApiDocumentSource(
            sequence: ApiSequence<Document>(repository: self,
                                            url: url(.documents(page: 1, filter: filter))))
    }

    func download(documentID: UInt) async -> URL? {
        let request = request(.download(documentId: documentID))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                Logger.shared.trace("Downloading document: Status was not 200")
                return nil
            }

            guard let response = response as? HTTPURLResponse else {
                Logger.shared.trace("Cannot get http response")
                return nil
            }

            guard let suggestedFilename = response.suggestedFilename else {
                Logger.shared.trace("Cannot get ")
                return nil
            }

            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(suggestedFilename)

            try data.write(to: temporaryFileURL, options: .atomic)
            try await Task.sleep(for: .seconds(0.2)) // wait a little bit for the data to be flushed
            return temporaryFileURL

        } catch {
            print(error)
            return nil
        }
    }

    func tag(id: UInt) async -> Tag? { return await get(Tag.self, id: id) }

    func create(tag: ProtoTag) async throws -> Tag {
        return try await create(element: tag, endpoint: .createTag(), returns: Tag.self)
    }

    func update(tag: Tag) async throws -> Tag {
        return try await update(element: tag, endpoint: .tag(id: tag.id))
    }

    func delete(tag: Tag) async throws {
        try await delete(element: tag, endpoint: .tag(id: tag.id))
    }

    func tags() async -> [Tag] { return await all(Tag.self) }

    func correspondent(id: UInt) async -> Correspondent? { return await get(Correspondent.self, id: id) }

    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent {
        return try await create(element: correspondent,
                                endpoint: .createCorrespondent(),
                                returns: Correspondent.self)
    }

    func update(correspondent: Correspondent) async throws -> Correspondent {
        return try await update(element: correspondent,
                                endpoint: .correspondent(id: correspondent.id))
    }

    func delete(correspondent: Correspondent) async throws {
        return try await delete(element: correspondent,
                                endpoint: .correspondent(id: correspondent.id))
    }

    func correspondents() async -> [Correspondent] { return await all(Correspondent.self) }

    func documentType(id: UInt) async -> DocumentType? { return await get(DocumentType.self, id: id) }

    func create(documentType: ProtoDocumentType) async throws -> DocumentType {
        return try await create(element: documentType,
                                endpoint: .createDocumentType(),
                                returns: DocumentType.self)
    }

    func update(documentType: DocumentType) async throws -> DocumentType {
        return try await update(element: documentType,
                                endpoint: .documentType(id: documentType.id))
    }

    func delete(documentType: DocumentType) async throws {
        return try await delete(element: documentType,
                                endpoint: .documentType(id: documentType.id))
    }

    func documentTypes() async -> [DocumentType] { return await all(DocumentType.self) }

    func document(id: UInt) async -> Document? { return await get(Document.self, id: id) }

    func users() async -> [User] { return await all(User.self) }

    func thumbnail(document: Document) async -> (Bool, Image?) {
        guard let data = await thumbnailData(document: document) else {
            return (false, nil)
        }
        guard let uiImage = UIImage(data: data) else {
            return (false, nil)
        }
        let image = Image(uiImage: uiImage)
        return (false, image)
    }

    func thumbnailData(document: Document) async -> Data? {
        let url = url(Endpoint.thumbnail(documentId: document.id))

        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        connection.extraHeaders.apply(toRequest: &request)

        do {
            let (data, res) = try await URLSession.shared.data(for: request)

            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                return nil
            }

            return data
        } catch { return nil }
    }

    // MARK: Saved views

    func savedViews() async -> [SavedView] {
        return await all(SavedView.self)
    }

    func create(savedView view: ProtoSavedView) async throws -> SavedView {
        return try await create(element: view, endpoint: .createSavedView(), returns: SavedView.self)
    }

    func update(savedView view: SavedView) async throws -> SavedView {
        return try await update(element: view, endpoint: .savedView(id: view.id))
    }

    func delete(savedView view: SavedView) async throws {
        try await delete(element: view, endpoint: .savedView(id: view.id))
    }

    // MARK: Storage paths

    func storagePaths() async -> [StoragePath] {
        return await all(StoragePath.self)
    }

    func create(storagePath: ProtoStoragePath) async throws -> StoragePath {
        return try await create(element: storagePath, endpoint: .createStoragePath(), returns: StoragePath.self)
    }

    func update(storagePath: StoragePath) async throws -> StoragePath {
        return try await update(element: storagePath, endpoint: .savedView(id: storagePath.id))
    }

    func delete(storagePath: StoragePath) async throws {
        try await delete(element: storagePath, endpoint: .storagePath(id: storagePath.id))
    }

    private struct UiSettingsResponse: Codable {
        var user: User
    }

    func currentUser() async throws -> User {
        let request = request(.uiSettings())

        let (data, res) = try await URLSession.shared.data(for: request)

        guard (res as? HTTPURLResponse)?.statusCode == 200 else {
            throw CrudApiError(operation: .read, type: UiSettingsResponse.self, status: nil)
        }

        let uiSettings = try decoder.decode(UiSettingsResponse.self, from: data)
        return uiSettings.user
    }

    func tasks() async -> [PaperlessTask] {
        let request = request(.tasks())

        do {
            let (data, res) = try await URLSession.shared.data(for: request)

            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                throw CrudApiError(operation: .read, type: [PaperlessTask].self, status: nil)
            }

            return try decoder.decode([PaperlessTask].self, from: data)
        } catch {
            Logger.shared.debug("Unable to load tasks: \(error)")
            return []
        }
    }
}
