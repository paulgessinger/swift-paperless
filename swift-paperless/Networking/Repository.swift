//
//  Repository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.03.23.
//

import Foundation
import SwiftUI

protocol Model {}

protocol Repository {
    func updateDocument(_ document: Document) async throws
    func deleteDocument(_ document: Document) async throws
    func createDocument(_ document: ProtoDocument, file: URL) async throws

    func get<T: Decodable & Model>(_ type: T.Type, id: UInt, path: String) async -> T?
    func all<T: Decodable & Model>(_ type: T.Type) async -> [T]

    func documents(filter: FilterState) -> any DocumentSource

    // @TODO: Remove UIImage
    func thumbnail(document: Document) async -> (Bool, Image?)

    func download(documentID: UInt) async -> URL?
    func getSearchCompletion(term: String, limit: UInt) async -> [String]
}

class NullRepository: Repository {
    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? { return nil }
    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func all<T: Decodable & Model>(_ type: T.Type) async -> [T] { return [] }
    func get<T: Decodable & Model>(_ type: T.Type, id: UInt, path: String) async -> T? { return nil }

    func documents(filter: FilterState) -> any DocumentSource {
        return NullDocumentSource()
    }

    func thumbnail(document: Document) async -> (Bool, Image?) { return (false, nil) }
}

// - MARK: DocumentSource
protocol DocumentSource {
    func fetch(limit: UInt) async -> [Document]
    func hasMore() async -> Bool
}

class NullDocumentSource: DocumentSource {
    func fetch(limit: UInt) async -> [Document] { return [] }
    func hasMore() async -> Bool { return false }
}
