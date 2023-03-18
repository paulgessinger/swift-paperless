//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
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
                        queryItems: [URLQueryItem(name: "per_page", value: String(100000))])
    }

    static func documentTypes() -> Endpoint {
        return Endpoint(path: "/api/document_types/", queryItems: [URLQueryItem(name: "per_page", value: String(100000))])
    }

    static func tags() -> Endpoint {
        return Endpoint(path: "/api/tags/", queryItems: [URLQueryItem(name: "per_page", value: String(100000))])
    }

    static func createDocument() -> Endpoint {
        return Endpoint(path: "/api/documents/post_document/", queryItems: [])
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

protocol Repository {
    func updateDocument(_ document: Document) async throws
    func deleteDocument(_ document: Document) async throws
    func createDocument(_ document: ProtoDocument, file: URL) async throws

    func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T?

    // @TODO: Remove UIImage
    func getImage(document: Document) async -> (Bool, UIImage?)
    func getImage(url: URL?) async -> UIImage?

    // @TODO: Refactor to make generic
    func getDocuments(url: URL) async -> ListResponse<Document>?

    func getPreviewImage(documentID: UInt) async -> URL?
    func getSearchCompletion(term: String, limit: UInt) async -> [String]

    // @TODO: Remove this, shouldn't be in protocol
    func request(url: URL) -> URLRequest
    func url(_ endpoint: Endpoint) -> URL?
}

enum APIError: Error {
    case encodingFailed
    case putFailed
    case deleteFailed
    case postError(status: Int, body: String)
}

class NullRepository: Repository {
    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}
    func getDocuments(url: URL) async -> ListResponse<Document>? { return nil }
    func getPreviewImage(documentID: UInt) async -> URL? { return nil }
    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T? { return nil }

    func getImage(document: Document) async -> (Bool, UIImage?) { return (false, nil) }

    func getImage(url: URL?) async -> UIImage? { return nil }

    // @TODO: Remove this, shouldn't be in protocol
    func request(url: URL) -> URLRequest {
        return URLRequest(url: URL(string: "http://example.com")!)
    }

    func url(_ endpoint: Endpoint) -> URL? { return nil }
}

class ApiRepository: Repository {
    let apiHost: String
    let apiToken: String

    init(apiHost: String, apiToken: String) {
        self.apiHost = apiHost
        self.apiToken = apiToken
    }

    func url(_ endpoint: Endpoint) -> URL? {
        return endpoint.url(host: apiHost)
    }

    func updateDocument(_ document: Document) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(document)

        var request = request(url: url(Endpoint.document(id: document.id))!)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json

        let (data, response) = try await URLSession.shared.data(for: request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 200 {
            print("Saving document: Status was not 200 but \(statusCode)")
            print(String(data: data, encoding: .utf8)!)
            throw APIError.putFailed
        }
    }

    func createDocument(_ document: ProtoDocument, file: URL) async throws {
        var request = request(url: url(Endpoint.createDocument())!)

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

                throw APIError.postError(status: hres.statusCode, body: body)
            }
        } catch {
            print("Error uploading: \(error)")
            throw error
        }
    }

    func deleteDocument(_ document: Document) async throws {
        var request = request(url: url(Endpoint.document(id: document.id))!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 204 {
            print("Delete document: Status was not 204 but \(statusCode)")
            print(String(data: data, encoding: .utf8)!)
            throw APIError.deleteFailed
        }
    }

    func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; version=2", forHTTPHeaderField: "Accept")
        return request
    }

    func getDocuments(url: URL) async -> ListResponse<Document>? {
        var request = URLRequest(url: url)
        request.setValue("Token \(apiToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            do {
                let decoded = try decoder.decode(ListResponse<Document>.self, from: data)
                return decoded
            } catch let DecodingError.dataCorrupted(context) {
                print(context)
                return nil
            } catch let DecodingError.keyNotFound(key, context) {
                print("Key '\(key)' not found:", context.debugDescription)
                print("codingPath:", context.codingPath)
                return nil
            } catch let DecodingError.valueNotFound(value, context) {
                print("Value '\(value)' not found:", context.debugDescription)
                print("codingPath:", context.codingPath)
                return nil
            } catch let DecodingError.typeMismatch(type, context) {
                print("Type '\(type)' mismatch:", context.debugDescription)
                print("codingPath:", context.codingPath)
                return nil
            } catch {
                print(String(decoding: data, as: UTF8.self))
                print(error)
                return nil
            }
        } catch {
            print(error)
            return nil
        }
    }

    func getPreviewImage(documentID: UInt) async -> URL? {
        guard let url =
            URL(string: "https://\(apiHost)/api/documents/\(documentID)/download/")
        else {
            return nil
        }

//    print(url)

        let request = request(url: url)

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
        guard let url = url(Endpoint.searchAutocomplete(term: term, limit: limit)) else {
            fatalError("Invalid URL")
        }

        let request = request(url: url)

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

    func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T? {
        guard let url = URL(string: "https://\(apiHost)/api/\(path)/\(id)/") else {
            return nil
        }

        let request = request(url: url)

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

    func getImage(document: Document) async -> (Bool, UIImage?) {
        // @TODO: Add limited size caching
//        if let image = thumbnailCache[document] {
//            return (true, image)
//        }

        let image = await getImage(url: URL(string: "https://\(apiHost)/api/documents/\(document.id)/thumb/"))

//        thumbnailCache[document] = image
//        if thumbnailCache.count > DocumentStore.maxThumbnailCacheSize {
//            thumbnailCache.removeFirst(DocumentStore.maxThumbnailCacheSize - thumbnailCache.count)
//        }
        return (false, image)
    }

    func getImage(url: URL?) async -> UIImage? {
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

            return UIImage(data: data)
        } catch { return nil }
    }
}
