//
//  PreviewRepository.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 26.03.23.
//

import DataModel
import GameplayKit
import os
import SwiftUI

actor PreviewDocumentSource: DocumentSource {
    typealias DocumentSequence = [Document]

    var sequence: DocumentSequence

    init(sequence: DocumentSequence) {
        self.sequence = sequence
    }

    func fetch(limit: UInt) async -> [Document] {
        Array(sequence.prefix(Int(limit)))
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

actor PreviewRepository: Repository {
    private var documents: [UInt: Document]
    private let tags: [UInt: Tag]
    private let documentTypes: [UInt: DocumentType]
    private let correspondents: [UInt: Correspondent]
    private let storagePaths: [UInt: StoragePath]
    private let tasks: [PaperlessTask]
    private let users: [User]
    private let groups: [UserGroup]

    private let downloadDelay: Double

    init(downloadDelay: Double = 0.0) {
        self.downloadDelay = downloadDelay

        users = [
            User(id: 1, isSuperUser: true, username: "superperson"),
            User(id: 2, isSuperUser: false, username: "joeschmoe"),
        ]

        groups = [
            UserGroup(id: 1, name: "Crew"),
            UserGroup(id: 2, name: "Staff"),
        ]

        let tags = [Tag]([
            .init(id: 1, isInboxTag: true, name: "Inbox", slug: "inbox", color: Color.purple.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 2, isInboxTag: false, name: "Bank", slug: "bank", color: Color.blue.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 3, isInboxTag: false, name: "Travel Document", slug: "traveldoc", color: Color.green.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 4, isInboxTag: false, name: "Important", slug: "important", color: Color.red.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 5, isInboxTag: false, name: "Book", slug: "book", color: Color.yellow.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
            .init(id: 6, isInboxTag: false, name: "I am a very long tag name that will not fit in most places in the UI", slug: "very_long", color: Color.red.hex, match: "", matchingAlgorithm: .auto, isInsensitive: true),
        ]).reduce(into: [UInt: Tag]()) {
            $0[$1.id] = $1
        }

        let correspondents = [Correspondent]([
            .init(id: 1, documentCount: 2, name: "McMillan", slug: "mcmillan", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 2, documentCount: 21, name: "Credit Suisse", slug: "cs", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 3, documentCount: 66, name: "UBS", slug: "ubs", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 4, documentCount: 4, name: "Home", slug: "home", matchingAlgorithm: .auto, match: "", isInsensitive: true),
        ]).reduce(into: [UInt: Correspondent]()) {
            $0[$1.id] = $1
        }

        let documentTypes = [DocumentType]([
            .init(id: 1, name: "Letter", slug: "letter", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 2, name: "Invoice", slug: "invoice", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 3, name: "Receipt", slug: "receipt", match: "", matchingAlgorithm: .none, isInsensitive: false),
            .init(id: 4, name: "Bank Statement", slug: "bank-statement", match: "", matchingAlgorithm: .none, isInsensitive: false),
        ]).reduce(into: [UInt: DocumentType]()) {
            $0[$1.id] = $1
        }

        let storagePaths = [StoragePath]([
            .init(id: 1, name: "Path A", path: "aaa", slug: "path_a", matchingAlgorithm: .auto, match: "", isInsensitive: true),
            .init(id: 2, name: "Path B", path: "bbb", slug: "path_b", matchingAlgorithm: .auto, match: "", isInsensitive: true),
        ]).reduce(into: [UInt: StoragePath]()) {
            $0[$1.id] = $1
        }

        var documents: [UInt: Document] = [:]

        var generator = SeededGenerator(seed: 43)

        let dt = { () -> UInt? in
            if Float.random(in: 0 ..< 1.0, using: &generator) < 0.2 {
                return nil
            }
            return documentTypes.map(\.value.id).sorted().randomElement(using: &generator)
        }

        let corr = { () -> UInt? in
            if Float.random(in: 0 ..< 1.0, using: &generator) < 0.2 {
                return nil
            }
            //            return UInt(self.correspondents.count)
            //            return UInt(Int.random(in: 1..<self.correspondents.count + 1, using: &generator))
            return correspondents.map(\.value.id).sorted().randomElement(using: &generator)
        }

        let t = { () -> [UInt] in
            var result: Set<UInt> = []
            for _ in 0 ..< Int.random(in: 0 ..< 4, using: &generator) {
                if let id = tags.map(\.value.id).sorted().randomElement(using: &generator) {
                    result.insert(id)
                }
            }
            return result.map { $0 }
        }

        let p = { () -> UInt? in
            if Float.random(in: 0 ..< 1.0, using: &generator) < 0.2 {
                return nil
            }
            return storagePaths.map(\.value.id).sorted().randomElement(using: &generator)
        }

        var maxAsn: UInt = 0
        let asn = { () -> UInt? in
            if Float.random(in: 0 ..< 1.0, using: &generator) < 0.5 {
                return nil
            }
            maxAsn += 1
            return maxAsn
        }

        let notes: [Document.Note] = [
            .init(id: 1, note: "Hallo", created: .now),
            .init(id: 2, note: "Another note", created: .now),
        ]

        for i in 0 ..< 30 {
            documents[UInt(i)] = .init(id: UInt(i),
                                       title: "Document \(i + 1)",
                                       asn: asn(),
                                       documentType: dt(),
                                       correspondent: corr(),
                                       created: .now,
                                       tags: t(),
                                       added: .now,
                                       modified: .now,
                                       storagePath: p(),
                                       notes: notes)
        }

        documents[2]?.title = "I am a very long document title that will not."

        self.documents = documents
        self.correspondents = correspondents
        self.tags = tags
        self.documentTypes = documentTypes
        self.storagePaths = storagePaths

        tasks = [
            PaperlessTask(
                id: 2748,
                taskId: UUID(uuidString: "ef16d8fb-c495-4850-92b8-73a64109674e")!,
                taskFileName: "2021-05-04--Letter_Vorläufiger Bescheid Promotion__DOCT.pdf",
                dateCreated: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
                dateDone: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
                type: .file,
                status: .SUCCESS,
                result: "Success. New document id 2232 created",
                acknowledged: false,
                relatedDocument: "22"
            ),
            PaperlessTask(
                id: 2749,
                taskId: UUID(uuidString: "ef16d8fb-c495-4850-92b8-73a64109674e")!,
                taskFileName: nil,
                dateCreated: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
                dateDone: nil,
                type: .file,
                status: .SUCCESS,
                result: "Success. New document id 2232 created",
                acknowledged: false,
                relatedDocument: "1999991"
            ),
            PaperlessTask(
                id: 2750,
                taskId: UUID(uuidString: "ef16d8fb-c495-4850-92b8-73a64109674e")!,
                taskFileName: "2022-12-22--Statement_ELSTER - ESt unbeschränkt (ESt 1 A) - Einkommensteuererklärung unbeschränkte SteSteuer__Steuer.pdf",
                dateCreated: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
                dateDone: nil,
                type: .file,
                status: .FAILURE,
                result: "2024-04-30 ING Ertragsabrechnung_20240430.pdf.pdf: Not consuming 2024-04-30 ING Ertragsabrechnung_20240430.pdf.pdf: It is a duplicate of Ertragsabrechnung_20240430.pdf (#2488)",
                acknowledged: false,
                relatedDocument: nil
            ),
        ]
    }

    func nextAsn() async -> UInt {
        (documents.compactMap(\.value.asn).max() ?? 0) + 1
    }

    func update(document: Document) async throws -> Document { document }
    func delete(document _: Document) async throws {}
    func create(document _: ProtoDocument, file _: URL) async throws {}

    func download(documentID _: UInt, progress: (@Sendable (Double) -> Void)? = nil) async throws -> URL? {
        var elapsed = 0.0
        for i in 1 ... 10 {
            try? await Task.sleep(for: .seconds(downloadDelay / 10.0))
            elapsed = Double(i) / 10.0 * downloadDelay
            progress?(elapsed)
        }
        return Bundle.main.url(forResource: "demo2", withExtension: "pdf")
    }

    func tag(id: UInt) async -> Tag? { tags[id] }
    func create(tag _: ProtoTag) async throws -> Tag { throw NotImplemented() }
    func update(tag: Tag) async throws -> Tag { tag }
    func delete(tag _: Tag) async throws {}

    func tags() async -> [Tag] { tags.map(\.value) }

    func correspondent(id: UInt) async -> Correspondent? { correspondents[id] }
    func create(correspondent _: ProtoCorrespondent) async throws -> Correspondent { throw NotImplemented() }
    func update(correspondent _: Correspondent) async throws -> Correspondent { throw NotImplemented() }
    func delete(correspondent _: Correspondent) async throws {}
    func correspondents() async -> [Correspondent] { correspondents.map(\.value) }

    func documentType(id: UInt) async -> DocumentType? { documentTypes[id] }
    func create(documentType _: ProtoDocumentType) async throws -> DocumentType { throw NotImplemented() }
    func update(documentType _: DocumentType) async throws -> DocumentType { throw NotImplemented() }
    func delete(documentType _: DocumentType) async throws {}
    func documentTypes() async -> [DocumentType] { documentTypes.map(\.value) }

    func document(id: UInt) async -> Document? { documents[id] }

    func document(asn: UInt) async -> Document? {
        documents.first(where: { $0.value.asn == asn })?.value
    }

    func metadata(documentId _: UInt) async throws -> Metadata {
        Metadata(
            originalChecksum: "4e3db09db50373773325e278e4a9919",
            originalSize: 61337,
            originalMimeType: "application/pdf",
            mediaFilename: "username/2024/07/2024-07-18--Invoice.pdf",
            hasArchiveVersion: true,
            originalMetadata: [Metadata.Item](),
            archiveChecksum: "4e3db09db50373773325e278e4a9919",
            archiveMediaFilename: "username/2024/07/2024-07-18--Invoice.pdf",
            originalFilename: "invoice.pdf",
            archiveSize: nil,
            archiveMetadata: [Metadata.Item](),
            lang: "de"
        )
    }

    struct NoteError: Error {}

    func createNote(documentId: UInt, note: ProtoDocument.Note) async throws -> [Document.Note] {
        guard var document = documents[documentId] else {
            throw NoteError()
        }

        let nextId = (document.notes.map(\.id).max() ?? 0) + 1
        document.notes.append(Document.Note(id: nextId, note: note.note, created: .now))

        documents[documentId] = document
        return document.notes
    }

    func deleteNote(id: UInt, documentId: UInt) async throws -> [Document.Note] {
        guard var document = documents[documentId] else {
            throw NoteError()
        }

        document.notes = document.notes.filter { $0.id != id }
        documents[documentId] = document
        return document.notes
    }

    func documents(filter _: FilterState) -> any DocumentSource {
        PreviewDocumentSource(sequence: documents.map(\.value).sorted(by: { a, b in a.id < b.id }))
    }

    func thumbnail(document: Document) async throws -> Image? {
        let data = try await thumbnailData(document: document)
        let image = Image(data: data)
        return image
    }

    func thumbnailData(document: Document) async throws -> Data {
        let request = URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/1500/1000")!)

        do {
            let (data, _) = try await URLSession.shared.getData(for: request)

            return data
        } catch {
            Logger.shared.error("Unable to get preview document thumbnail (somehow): \(error)")
            throw error
        }
    }

    nonisolated
    func thumbnailRequest(document: Document) throws -> URLRequest {
        URLRequest(url: URL(string: "https://picsum.photos/id/\(document.id + 100)/1500/1000")!)
    }

    func suggestions(documentId _: UInt) async -> Suggestions {
        .init(correspondents: [1], tags: [2, 3], documentTypes: [4], storagePaths: [2], dates: [.now, .now.advanced(by: 86400)])
    }

    struct NotImplemented: Error {}

    func savedViews() async -> [SavedView] { [] }
    func create(savedView _: ProtoSavedView) async throws -> SavedView { throw NotImplemented() }
    func update(savedView: SavedView) async throws -> SavedView { savedView }
    func delete(savedView _: SavedView) async throws { throw NotImplemented() }

    func storagePaths() async -> [StoragePath] { storagePaths.map(\.value) }
    func create(storagePath _: ProtoStoragePath) async throws -> StoragePath { throw NotImplemented() }
    func update(storagePath: StoragePath) async throws -> StoragePath { storagePath }
    func delete(storagePath _: StoragePath) async throws { throw NotImplemented() }

    func currentUser() async throws -> User {
        .init(id: 1, isSuperUser: true, username: "user")
    }

    func users() async -> [User] { users }
    func groups() async throws -> [UserGroup] { groups }

    func tasks() async -> [PaperlessTask] { tasks }
    func task(id _: UInt) async throws -> PaperlessTask? { nil }

    func task(id: UInt) throws -> PaperlessTask? { tasks.first { $0.id == id } }

    func acknowledge(tasks _: [UInt]) async throws {}

    nonisolated
    var delegate: (any URLSessionDelegate)? { nil }

    func uiSettings() async -> UISettings {
        UISettings(
            user: User(id: 1, isSuperUser: true, username: "user"),
            settings: UISettingsSettings(),
            permissions: UserPermissions.full
        )
    }
}
