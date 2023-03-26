//
//  PreviewRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.03.23.
//

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

class PreviewRepository: Repository {
    private let documents = [Document]([
        .init(id: 1, title: "Document One", documentType: 1, correspondent: 1, created: .now, tags: [1]),
        .init(id: 2, title: "Document Two", documentType: 2, correspondent: 2, created: .now, tags: [1, 2]),
        .init(id: 3, title: "Document Three", documentType: 3, correspondent: 3, created: .now, tags: [2, 4, 1]),
    ]).reduce(into: [UInt: Document]()) {
        $0[$1.id] = $1
    }

    private let tags = [Tag]([
        .init(id: 1, isInboxTag: true, name: "Inbox", slug: "inbox", color: .purple, textColor: .white),
        .init(id: 2, isInboxTag: false, name: "Bank", slug: "bank", color: .blue, textColor: .white),
        .init(id: 3, isInboxTag: false, name: "Travel Document", slug: "traveldoc", color: .green, textColor: .white),
        .init(id: 4, isInboxTag: false, name: "Important", slug: "important", color: .red, textColor: .white),
    ]).reduce(into: [UInt: Tag]()) {
        $0[$1.id] = $1
    }

    private let correspondents = [Correspondent]([
        .init(id: 1, documentCount: 2, isInsensitive: true, name: "McMillan", slug: "mcmillan"),
        .init(id: 2, documentCount: 21, isInsensitive: true, name: "Credit Suisse", slug: "cs"),
        .init(id: 3, documentCount: 66, isInsensitive: true, name: "UBS", slug: "ubs"),
    ]).reduce(into: [UInt: Correspondent]()) {
        $0[$1.id] = $1
    }

    private let documentTypes = [DocumentType]([
        .init(id: 1, name: "Letter", slug: "letter"),
        .init(id: 2, name: "Invoice", slug: "invoice"),
        .init(id: 3, name: "Receipt", slug: "receipt"),
    ]).reduce(into: [UInt: DocumentType]()) {
        $0[$1.id] = $1
    }

    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? { return nil }
    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func tag(id: UInt) async -> Tag? { return tags[id] }
    func tags() async -> [Tag] { return tags.map { $0.value } }

    func correspondent(id: UInt) async -> Correspondent? { return correspondents[id] }
    func correspondents() async -> [Correspondent] { return correspondents.map { $0.value } }

    func documentTypes(id: UInt) async -> DocumentType? { return documentTypes[id] }
    func documentTypes() async -> [DocumentType] { return documentTypes.map { $0.value } }

    func document(id: UInt) async -> Document? { return documents[id] }

    func documents(filter: FilterState) -> any DocumentSource {
        return PreviewDocumentSource(sequence: documents.map { $0.value })
    }

    func thumbnail(document: Document) async -> (Bool, Image?) {
        let request = URLRequest(url: URL(string: "https://picsum.photos/200")!)

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
}
