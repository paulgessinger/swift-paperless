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
        .init(id: 1, title: "Document One", created: .now, tags: [1]),
        .init(id: 2, title: "Document Two", created: .now, tags: [1, 2]),
        .init(id: 3, title: "Document Three", created: .now, tags: [2]),
    ]).reduce(into: [UInt: Document]()) {
        $0[$1.id] = $1
    }

    private let tags = [Tag]([
        .init(id: 1, isInboxTag: true, name: "Inbox", slug: "inbox", color: .red, textColor: .white),
        .init(id: 2, isInboxTag: false, name: "Bank", slug: "bank", color: .blue, textColor: .white),
    ]).reduce(into: [UInt: Tag]()) {
        $0[$1.id] = $1
    }

    func updateDocument(_ document: Document) async throws {}
    func deleteDocument(_ document: Document) async throws {}
    func createDocument(_ document: ProtoDocument, file: URL) async throws {}

    func download(documentID: UInt) async -> URL? { return nil }
    func getSearchCompletion(term: String, limit: UInt) async -> [String] { return [] }

    func tag(id: UInt) async -> Tag? { return tags[id] }
    func tags() async -> [Tag] { return tags.map { $0.value } }

    func correspondent(id: UInt) async -> Correspondent? { return nil }
    func correspondents() async -> [Correspondent] { return [] }

    func documentTypes(id: UInt) async -> DocumentType? { return nil }
    func documentTypes() async -> [DocumentType] { return [] }

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
