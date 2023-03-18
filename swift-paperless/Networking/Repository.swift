//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import Foundation
import UIKit

protocol Repository {
    func updateDocument(_ document: Document) async throws
    func deleteDocument(_ document: Document) async throws
    func createDocument(_ document: ProtoDocument, file: URL) async throws

    func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T?

    func documents(filter: FilterState) -> any DocumentSource

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

class NullRepository: Repository {
    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}
    func getDocuments(url: URL) async -> ListResponse<Document>? { return nil }
    func getPreviewImage(documentID: UInt) async -> URL? { return nil }
    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T? { return nil }

    func documents(filter: FilterState) -> any DocumentSource {
        return NullDocumentSource()
//        return ApiDocumentSequence(repository: self, url: URL(string: "http://example.com")!)
    }

    func getImage(document: Document) async -> (Bool, UIImage?) { return (false, nil) }

    func getImage(url: URL?) async -> UIImage? { return nil }

    // @TODO: Remove this, shouldn't be in protocol
    func request(url: URL) -> URLRequest {
        return URLRequest(url: URL(string: "http://example.com")!)
    }

    func url(_ endpoint: Endpoint) -> URL? { return nil }
}

// - MARK: DocumentSource
protocol DocumentSource {
    func fetch(limit: UInt) async -> [Document]
}

class NullDocumentSource: DocumentSource {
    func fetch(limit: UInt) async -> [Document] { return [] }
}
