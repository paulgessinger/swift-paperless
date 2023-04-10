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
        generator = GKMersenneTwisterRandomSource(seed: seed)
    }

    mutating func next() -> UInt64 {
        let next1 = UInt64(bitPattern: Int64(generator.nextInt()))
        let next2 = UInt64(bitPattern: Int64(generator.nextInt()))
        return next1 ^ (next2 << 32)
    }
}

class PreviewRepository: Repository {
//    private let documents = [Document]([
//        .init(id: 1, title: "Document One", documentType: documentTypes.map{$0.value.id}.randomElement(), correspondent: 1, created: .now, tags: [1]),
//        .init(id: 2, title: "Document Two", documentType: 2, correspondent: 2, created: .now, tags: [1, 2]),
//        .init(id: 3, title: "Document Three", documentType: 3, correspondent: 3, created: .now, tags: [2, 4, 1]),
//    ]).reduce(into: [UInt: Document]()) {
//        $0[$1.id] = $1
//    }

    private var documents: [UInt: Document] {
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

        var result: [UInt: Document] = [:]

        for i in 0..<30 {
            result[UInt(i)] = .init(id: UInt(i),
                                    title: "Document \(i + 1)",
                                    documentType: dt(),
                                    correspondent: corr(),
                                    created: .now,
                                    tags: t())
        }

        return result

//        let gen = {() -> Document}
//
//        return [Document]([
//            .init(id: 1, title: "Document One", documentType: dt(), correspondent: 1, created: .now, tags: [1]),
//            .init(id: 2, title: "Document Two", documentType: 2, correspondent: 2, created: .now, tags: [1, 2]),
//            .init(id: 3, title: "Document Three", documentType: 3, correspondent: 3, created: .now, tags: [2, 4, 1]),
//        ]).reduce(into: [UInt: Document]()) {
//            $0[$1.id] = $1
//        }
    }

    private let tags = [Tag]([
        .init(id: 1, isInboxTag: true, name: "Inbox", slug: "inbox", color: .purple, textColor: .white),
        .init(id: 2, isInboxTag: false, name: "Bank", slug: "bank", color: .blue, textColor: .white),
        .init(id: 3, isInboxTag: false, name: "Travel Document", slug: "traveldoc", color: .green, textColor: .white),
        .init(id: 4, isInboxTag: false, name: "Important", slug: "important", color: .red, textColor: .white),
        .init(id: 5, isInboxTag: false, name: "Book", slug: "book", color: .yellow, textColor: .white),
    ]).reduce(into: [UInt: Tag]()) {
        $0[$1.id] = $1
    }

    private let correspondents = [Correspondent]([
        .init(id: 1, documentCount: 2, isInsensitive: true, name: "McMillan", slug: "mcmillan"),
        .init(id: 2, documentCount: 21, isInsensitive: true, name: "Credit Suisse", slug: "cs"),
        .init(id: 3, documentCount: 66, isInsensitive: true, name: "UBS", slug: "ubs"),
        .init(id: 4, documentCount: 4, isInsensitive: true, name: "Home", slug: "home"),
    ]).reduce(into: [UInt: Correspondent]()) {
        $0[$1.id] = $1
    }

    private let documentTypes = [DocumentType]([
        .init(id: 1, name: "Letter", slug: "letter"),
        .init(id: 2, name: "Invoice", slug: "invoice"),
        .init(id: 3, name: "Receipt", slug: "receipt"),
        .init(id: 4, name: "Bank Statement", slug: "bank-statement"),
    ]).reduce(into: [UInt: DocumentType]()) {
        $0[$1.id] = $1
    }

    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? {
        return Bundle.main.url(forResource: "demo", withExtension: "pdf")
    }

    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func tag(id: UInt) async -> Tag? { return tags[id] }
    func tags() async -> [Tag] { return tags.map { $0.value } }

    func correspondent(id: UInt) async -> Correspondent? { return correspondents[id] }
    func correspondents() async -> [Correspondent] { return correspondents.map { $0.value } }

    func documentType(id: UInt) async -> DocumentType? { return documentTypes[id] }
    func documentTypes() async -> [DocumentType] { return documentTypes.map { $0.value } }

    func document(id: UInt) async -> Document? { return documents[id] }

    func documents(filter: FilterState) -> any DocumentSource {
        return PreviewDocumentSource(sequence: documents.map { $0.value }.sorted(by: { a, b in a.id < b.id }))
    }

    func thumbnail(document: Document) async -> (Bool, Image?) {
        let request = URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/200")!)

        do {
            let (data, _) = try await URLSession.shared.data(for: request)

            guard let uiImage = UIImage(data: data) else { return (false, nil) }
            let image = Image(uiImage: uiImage)

            return (false, image)
        }
        catch {
            print(error)
            return (false, nil)
        }
    }

    func savedViews() async -> [SavedView] {
        return []
    }
}
