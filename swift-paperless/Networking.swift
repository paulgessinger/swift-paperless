//
//  Networking.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation

let API_TOKEN = "***REMOVED***"
let API_BASE_URL = "https://***REMOVED***/api/"
let API_HOST = "***REMOVED***"

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

    var url: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = API_HOST
        components.path = path
        components.queryItems = queryItems
        return components.url
    }
}

func getDocuments(url: URL) async -> ListResponse<Document>? {
//    guard let url = Endpoint.documents(page: page, query: query).url else {
//        fatalError("Invalid URL")
//    }

//    print(url)
//    print("Go getDocuments")

    var request = URLRequest(url: url)
    request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

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
        URL(string: "\(API_BASE_URL)documents/\(documentID)/download/")
    else {
        return nil
    }

//    print(url)

    let request = URLRequest.common(url: url)

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
    guard let url = Endpoint.searchAutocomplete(term: term, limit: limit).url else {
        fatalError("Invalid URL")
    }

    let request = URLRequest.common(url: url)

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

extension URLRequest {
    static func common(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; version=2", forHTTPHeaderField: "Accept")
        return request
    }
}
