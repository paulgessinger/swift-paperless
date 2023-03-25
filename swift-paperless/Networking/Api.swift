//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import SwiftUI
import UIKit

struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]
}

extension Endpoint {
    static func documents(page: UInt, filter: FilterState = FilterState()) -> Endpoint {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
        ]

        if let query = filter.searchText {
            queryItems.append(URLQueryItem(name: "query", value: query))
        }

//        if case let .notAssigned = filter.correspondent {
//            queryItems.append(URLQueryItem(name: "correspondent__id", value: "isnull"))
//        }

        switch filter.correspondent {
        case .any: break
        case .notAssigned:
            queryItems.append(URLQueryItem(name: "correspondent__isnull", value: "1"))
        case let .only(id):
            queryItems.append(URLQueryItem(name: "correspondent__id", value: String(id)))
        }

        switch filter.documentType {
        case .any: break
        case .notAssigned:
            queryItems.append(URLQueryItem(name: "document_type__isnull", value: "1"))
        case let .only(id):
            queryItems.append(URLQueryItem(name: "document_type__id", value: String(id)))
        }

        switch filter.tags {
        case .any: break
        case .notAssigned:
            queryItems.append(URLQueryItem(name: "is_tagged", value: "0"))
        case let .only(ids):
            queryItems.append(
                URLQueryItem(name: "tags__id__all",
                             value: ids.map { String($0) }.joined(separator: ",")))
        }

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
        default:
            fatalError("Invalid type")
        }
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
        components.queryItems = queryItems
        return components.url
    }
}

private struct ListResponse<Element>: Decodable
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

private let decoder: JSONDecoder = {
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
    d.keyDecodingStrategy = .convertFromSnakeCase
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

    init(repository: ApiRepository, url: URL) {
        self.repository = repository
        nextPage = url
    }

    func next() async -> Element? {
        guard !Task.isCancelled else {
            return nil
        }

        // if we have a current page loaded, return next element from that
        if let buffer = buffer, bufferIndex < buffer.count {
            defer { bufferIndex += 1 }
            return buffer[bufferIndex]
        }

        guard let url = nextPage else {
            hasMore = false
            return nil
        }

        do {
            let request = repository.request(url: url)
            let (data, _) = try await URLSession.shared.data(for: request)

            let decoded = try decoder.decode(ListResponse<Element>.self, from: data)

            guard !decoded.results.isEmpty else {
                hasMore = false
                return nil
            }

//            if Element.self is Document.Type {
//                print(url)
//                print("Got \(decoded.results.count)")
//            }

            nextPage = decoded.next
//            print("next: \(nextPage)")
            buffer = decoded.results
            bufferIndex = 1 // set to one because we return the first element immediately
            return decoded.results[0]

        } catch {
            print(error)
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
        return ApiDocumentSource(
            sequence: ApiSequence<Document>(repository: self,
                                            url: url(.documents(page: 1, filter: filter))))
    }

    func download(documentID: UInt) async -> URL? {
        let request = request(.download(documentId: documentID))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Getting image: Status was not 200")
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
//        print(suggestedFilename)

            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
//        let temporaryFilename = ProcessInfo().globallyUniqueString
            let temporaryFileURL = temporaryDirectoryURL.appendingPathComponent(suggestedFilename)
//        print(temporaryFileURL)

            try data.write(to: temporaryFileURL, options: .atomic)
            try await Task.sleep(for: .seconds(0.2)) // wait a little bit for the data to be flushed
            return temporaryFileURL

        } catch {
            print(error)
            return nil
        }
    }

    func getSearchCompletion(term: String, limit: UInt = 10) async -> [String] {
        let request = request(.searchAutocomplete(term: term, limit: limit))

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Getting image: Status was not 200")
                return []
            }

            return try decoder.decode([String].self, from: data)

        } catch {
            print(error)
            return []
        }
    }

    func get<T: Decodable & Model>(_ type: T.Type, id: UInt, path: String) async -> T? {
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

    func all<T: Decodable & Model>(_ type: T.Type) async -> [T] {
        let sequence = ApiSequence<T>(repository: self,
                                      url: url(.listAll(T.self)))
        return await Array(sequence)
    }

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
                fatalError("Did not get good response for image")
            }

//            try await Task.sleep(for: .seconds(2))

            guard let uiImage = UIImage(data: data) else { return nil }
            return Image(uiImage: uiImage)
        } catch { return nil }
    }
}
