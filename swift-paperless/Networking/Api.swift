//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import Semaphore
import SwiftUI
import UIKit

struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]
}

extension Endpoint {
    static func documents(page: UInt, filter: FilterState = FilterState(), pageSize: UInt = 100) -> Endpoint {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "truncate_content", value: "true"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]

        let rules = filter.rules
        queryItems += FilterRule.queryItems(for: rules)

        queryItems.append(.init(name: "ordering", value: "-created"))

        return Endpoint(
            path: "/api/documents/",
            queryItems: queryItems
        )
    }

    static func document(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(id)/", queryItems: [])
    }

    static func thumbnail(documentId: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(documentId)/thumb/", queryItems: [])
    }

    static func download(documentId: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(documentId)/download/", queryItems: [])
    }

    static func searchAutocomplete(term: String, limit: UInt = 10) -> Endpoint {
        return Endpoint(
            path: "/api/search/autocomplete/",
            queryItems: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func correspondents() -> Endpoint {
        return Endpoint(path: "/api/correspondents/",
                        queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func documentTypes() -> Endpoint {
        return Endpoint(path: "/api/document_types/", queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func tags() -> Endpoint {
        return Endpoint(path: "/api/tags/", queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createDocument() -> Endpoint {
        return Endpoint(path: "/api/documents/post_document/", queryItems: [])
    }

    static func listAll<T>(_ type: T.Type) -> Endpoint where T: Model {
        switch type {
        case is Correspondent.Type:
            return correspondents()
        case is DocumentType.Type:
            return documentTypes()
        case is Tag.Type:
            return tags()
        case is Document.Type:
            return documents(page: 1, filter: FilterState())
        case is SavedView.Type:
            return savedViews()
        default:
            fatalError("Invalid type")
        }
    }

    static func savedViews() -> Endpoint {
        return Endpoint(path: "/api/saved_views/",
                        queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createSavedView() -> Endpoint {
        return Endpoint(path: "/api/saved_views/",
                        queryItems: [])
    }

    static func single<T>(_ type: T.Type, id: UInt) -> Endpoint where T: Model {
        var segment = ""
        switch type {
        case is Correspondent.Type:
            segment = "correspondents"
        case is DocumentType.Type:
            segment = "document_types"
        case is Tag.Type:
            segment = "tags"
        case is Document.Type:
            return document(id: id)
        default:
            fatalError("Invalid type")
        }

        return Endpoint(path: "/api/\(segment)/\(id)/",
                        queryItems: [])
    }

    func url(host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}

struct ListResponse<Element>: Decodable
    where Element: Decodable
{
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Element]
}

enum DateDecodingError: Error {
    case invalidDate(string: String)
}

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

enum ApiError: Error {
    case encodingFailed
    case putFailed
    case deleteFailed
    case postError(status: Int, body: String)
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

class ApiRepository: Repository {
    private let connection: Connection

    init(connection: Connection) {
        self.connection = connection
    }

    private var apiHost: String {
        connection.host
    }

    private var apiToken: String {
        connection.token
    }

    func url(_ endpoint: Endpoint) -> URL {
        return endpoint.url(host: apiHost)!
    }

    func updateDocument(_ document: Document) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(document)

        var request = request(.document(id: document.id))
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json

        let (data, response) = try await URLSession.shared.data(for: request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
            print("Saving document: Status was not 200 but \(statusCode)")
            print(String(data: data, encoding: .utf8)!)
            throw ApiError.putFailed
        }
    }

    func createDocument(_ document: ProtoDocument, file: URL) async throws {
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

                throw ApiError.postError(status: hres.statusCode, body: body)
            }
        } catch {
            print("Error uploading: \(error)")
            throw error
        }
    }

    func deleteDocument(_ document: Document) async throws {
        var request = request(.document(id: document.id))
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 204 {
            print("Delete document: Status was not 204 but \(statusCode)")
            print(String(data: data, encoding: .utf8)!)
            throw ApiError.deleteFailed
        }
    }

    fileprivate func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; version=2", forHTTPHeaderField: "Accept")
        return request
    }

    fileprivate func request(_ endpoint: Endpoint) -> URLRequest {
        request(url: url(endpoint))
    }

    func documents(filter: FilterState) -> any DocumentSource {
        print(Endpoint.documents(page: 1, filter: filter).url(host: "THIS_IS_ON_PURPOSE"))
        return ApiDocumentSource(
            sequence: ApiSequence<Document>(repository: self,
                                            url: url(.documents(page: 1, filter: filter))))
    }

    func download(documentID: UInt) async -> URL? {
        let request = request(.download(documentId: documentID))
//        print(request.url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Downloading document: Status was not 200")
                return nil
            }

            guard let response = response as? HTTPURLResponse else {
                print("Cannot get http response")
                return nil
            }

            guard let suggestedFilename = response.suggestedFilename else {
                print("Cannot get ")
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

    func tag(id: UInt) async -> Tag? { return await get(Tag.self, id: id) }
    func tags() async -> [Tag] { return await all(Tag.self) }

    func correspondent(id: UInt) async -> Correspondent? { return await get(Correspondent.self, id: id) }
    func correspondents() async -> [Correspondent] { return await all(Correspondent.self) }

    func documentType(id: UInt) async -> DocumentType? { return await get(DocumentType.self, id: id) }
    func documentTypes() async -> [DocumentType] { return await all(DocumentType.self) }

    func document(id: UInt) async -> Document? { return await get(Document.self, id: id) }

    func thumbnail(document: Document) async -> (Bool, Image?) {
        let image = await getImage(url: url(Endpoint.thumbnail(documentId: document.id)))
        return (false, image)
    }

    private func getImage(url: URL?) async -> Image? {
        guard let url = url else { return nil }

//        print("Load image at \(url)")

        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: request)

            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                return nil
//                fatalError("Did not get good response for image")
            }

//            try await Task.sleep(for: .seconds(2))

            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        } catch { return nil }
    }

    func savedViews() async -> [SavedView] {
        return await all(SavedView.self)
    }

    func createSavedView(_ view: ProtoSavedView) async throws -> SavedView {
        var request = request(.createSavedView())
        print(request.url!)

        let body = try JSONEncoder().encode(view)
        print("Create saved view: \(String(describing: String(data: body, encoding: .utf8)!))")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 201 {
                let body = String(data: data, encoding: .utf8) ?? "No body"

                throw ApiError.postError(status: hres.statusCode, body: body)
            }

            let created = try decoder.decode(SavedView.self, from: data)
            return created
        } catch {
            print("Error uploading: \(error)")
            throw error
        }
    }
}
