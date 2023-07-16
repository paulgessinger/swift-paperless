//
//  PreviewRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.03.23.
//

import GameplayKit
import SwiftUI

struct PreviewDocumentSource: DocumentSource {
    typealias DocumentSequence = [Document]

    var sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    func fetch(limit: UInt) async -> [Document] {
        return Array(sequence.prefix(Int(limit)))
    }

    func hasMore() async -> Bool { false }
}

struct SeededGenerator: RandomNumberGenerator {
    let seed: UInt64
    private let generator: GKMersenneTwisterRandomSource

    init(seed: UInt64 = 0) {
        self.seed = seed
        self.generator = GKMersenneTwisterRandomSource(seed: seed)
    }

    mutating func next() -> UInt64 {
        let next1 = UInt64(bitPattern: Int64(generator.nextInt()))
        let next2 = UInt64(bitPattern: Int64(generator.nextInt()))
        return next1 ^ (next2 << 32)
    }
}

class PreviewRepository: Repository {
    private var documents: [UInt: Document]
    private var tags: [UInt: Tag]
    private var documentTypes: [UInt: DocumentType]
    private var correspondents: [UInt: Correspondent]
    private var storagePaths: [UInt: StoragePath]

    init() {
        self.tags = [Tag]([
            .init(id: 1, isInboxTag: true, name: "Inbox", slug: "inbox", color: Color.purple.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 2, isInboxTag: false, name: "Bank", slug: "bank", color: Color.blue.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 3, isInboxTag: false, name: "Travel Document", slug: "traveldoc", color: Color.green.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 4, isInboxTag: false, name: "Important", slug: "important", color: Color.red.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 5, isInboxTag: false, name: "Book", slug: "book", color: Color.yellow.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 6, isInboxTag: false, name: "I am a very long tag name that will not fit in most places in the UI", slug: "very_long", color: Color.red.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
        ]).reduce(into: [UInt: Tag]()) {
            $0[$1.id] = $1
        }

        self.correspondents = [Correspondent]([
            .init(id: 1, documentCount: 2, name: "McMillan", slug: "mcmillan", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 2, documentCount: 21, name: "Credit Suisse", slug: "cs", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 3, documentCount: 66, name: "UBS", slug: "ubs", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 4, documentCount: 4, name: "Home", slug: "home", matchingAlgorithm: .auto, match: "", isInsensitive: true),
        ]).reduce(into: [UInt: Correspondent]()) {
            $0[$1.id] = $1
        }

        self.documentTypes = [DocumentType]([
            .init(id: 1, name: "Letter", slug: "letter", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 2, name: "Invoice", slug: "invoice", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 3, name: "Receipt", slug: "receipt", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 4, name: "Bank Statement", slug: "bank-statement", match: "", matchingAlgorithm: .none, isInsensitive: false),
        ]).reduce(into: [UInt: DocumentType]()) {
            $0[$1.id] = $1
        }

        self.storagePaths = [StoragePath]([
            .init(id: 1, name: "Path A", path: "aaa", slug: "path_a", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 2, name: "Path B", path: "bbb", slug: "path_b", matchingAlgorithm: .auto, match: "", isInsensitive: true),
        ]).reduce(into: [UInt: StoragePath]()) {
            $0[$1.id] = $1
        }

        self.documents = [:]

        var generator = SeededGenerator(seed: 43)

        let dt = { () -> UInt? in
            if Float.random(in: 0..<1.0, using: &generator) < 0.2 {
                return nil
            }
            return self.documentTypes.map { $0.value.id }.sorted().randomElement(using: &generator)
        }

        let corr = { () -> UInt? in
            if Float.random(in: 0..<1.0, using: &generator) < 0.2 {
                return nil
            }
            //            return UInt(self.correspondents.count)
            //            return UInt(Int.random(in: 1..<self.correspondents.count + 1, using: &generator))
            return self.correspondents.map { $0.value.id }.sorted().randomElement(using: &generator)
        }

        let t = { () -> [UInt] in
            var result: Set<UInt> = []
            for _ in 0..<Int.random(in: 0..<4, using: &generator) {
                if let id = self.tags.map({ $0.value.id }).sorted().randomElement(using: &generator) {
                    result.insert(id)
                }
            }
            return result.map { $0 }
        }

        let p = { () -> UInt? in
            if Float.random(in: 0..<1.0, using: &generator) < 0.2 {
                return nil
            }
            return self.storagePaths.map { $0.value.id }.sorted().randomElement(using: &generator)
        }

        for i in 0..<30 {
            documents[UInt(i)] = .init(id: UInt(i),
                                       title: "Document \(i + 1)",
                                       documentType: dt(),
                                       correspondent: corr(),
                                       created: .now,
                                       tags: t(),
                                       storagePath: p())
        }

        documents[2]?.title = "I am a very long document title that will not fit into a single line."
    }

    func update(document: Document) async throws -> Document { document }
    func delete(document: Document) async throws {}
    func create(document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? {
        return Bundle.main.url(forResource: "demo", withExtension: "pdf")
    }

    func tag(id: UInt) async -> Tag? { return tags[id] }
    func create(tag: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func update(tag: Tag) async throws -> Tag { tag }
    func delete(tag: Tag) async throws {}

    func tags() async -> [Tag] { return tags.map { $0.value } }

    func correspondent(id: UInt) async -> Correspondent? { return correspondents[id] }
    func create(correspondent: ProtoCorrespondent) async throws -> Correspondent { throw NotImplemented() }
    func update(correspondent: Correspondent) async throws -> Correspondent { throw NotImplemented() }
    func delete(correspondent: Correspondent) async throws {}
    func correspondents() async -> [Correspondent] { return correspondents.map { $0.value } }

    func documentType(id: UInt) async -> DocumentType? { return documentTypes[id] }
    func create(documentType: ProtoDocumentType) async throws -> DocumentType { throw NotImplemented() }
    func update(documentType: DocumentType) async throws -> DocumentType { throw NotImplemented() }
    func delete(documentType: DocumentType) async throws {}
    func documentTypes() async -> [DocumentType] { return documentTypes.map { $0.value } }

    func document(id: UInt) async -> Document? { return documents[id] }

    func documents(filter: FilterState) -> any DocumentSource {
        return PreviewDocumentSource(sequence: documents.map { $0.value }.sorted(by: { a, b in a.id < b.id }))
    }

    func thumbnail(document: Document) async -> (Bool, Image?) {
        guard let data = await thumbnailData(document: document) else {
            print("No thumb data returned")
            return (false, nil)
        }

        guard let uiImage = UIImage(data: data) else { return (false, nil) }
        let image = Image(uiImage: uiImage)

        return (false, image)
    }

    func thumbnailData(document: Document) async -> Data? {
        let request = URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/200")!)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            return data
        }
        catch {
            print(error)
            return nil
        }
    }

    struct NotImplemented: Error {}

    func savedViews() async -> [SavedView] { return [] }
    func create(savedView: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func update(savedView: SavedView) async throws -> SavedView { savedView }
    func delete(savedView: SavedView) async throws { throw NotImplemented() }

    func storagePaths() async -> [StoragePath] { return storagePaths.map { $0.value } }
    func create(storagePath: ProtoStoragePath) async throws -> StoragePath { throw NotImplemented() }
    func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
    func delete(storagePath: StoragePath) async throws { throw NotImplemented() }

    func currentUser() async throws -> User {
        .init(id: 1, isSuperUser: true, username: "user")
    }

    func users() async -> [User] { [] }

    func tasks() async -> [PaperlessTask] { [] }
}
