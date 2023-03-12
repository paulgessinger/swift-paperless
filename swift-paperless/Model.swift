//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation
import OrderedCollections
import Semaphore
import SwiftUI

struct Document: Identifiable, Equatable, Hashable {
    var id: UInt
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
    var tags: [UInt]

    private(set) var added: String? = nil
    private(set) var storagePath: String? = nil
}

struct ProtoDocument: Codable {
    var title: String = ""
    var documentType: UInt? = nil
    var correspondent: UInt? = nil
    var tags: [UInt] = []
    var created: Date = .now
}

extension Document: Codable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(added, forKey: .added)
        try container.encode(title, forKey: .title)
        try container.encode(documentType, forKey: .documentType)
        try container.encode(correspondent, forKey: .correspondent)
        try container.encode(created, forKey: .created)
        try container.encode(tags, forKey: .tags)
        try container.encode(storagePath, forKey: .storagePath)
    }
}

struct Correspondent: Codable, Identifiable {
    var id: UInt
    var documentCount: UInt
    var isInsensitive: Bool
    var lastCorrespondence: Date?
    // match?
    var name: String
    var slug: String
}

struct DocumentType: Codable, Identifiable {
    var id: UInt
    var name: String
    var slug: String
}

struct Tag: Codable, Identifiable {
    var id: UInt
    var isInboxTag: Bool
    var name: String
    var slug: String
    @HexColor var color: Color
    @HexColor var textColor: Color

    static func placeholder(_ length: Int) -> Tag {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        let name = String((0 ..< length).map { _ in letters.randomElement()! })
        return .init(id: 0, isInboxTag: false, name: name, slug: "", color: Color.systemGroupedBackground, textColor: .white)
    }
}

extension Tag: Equatable, Hashable {
    static func == (lhs: Tag, rhs: Tag) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

protocol ListResponseProtocol {
    associatedtype ObjectType: Identifiable

    var results: [ObjectType] { get }
    var next: URL? { get }
}

struct ListResponse<Element>: Decodable, ListResponseProtocol
    where Element: Decodable, Element: Identifiable
{
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Element]
}

enum DateDecodingError: Error {
    case invalidDate(string: String)
}

enum APIError: Error {
    case encodingFailed
    case putFailed
    case deleteFailed
}

let decoder: JSONDecoder = {
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

// struct Documents : AsyncSequence {
//
// }

struct FilterState: Equatable {
    enum Filter: Equatable, Hashable {
        case any
        case notAssigned
        case only(id: UInt)
    }

    enum Tag: Equatable, Hashable {
        case any
        case notAssigned
        case only(ids: [UInt])
    }

    var correspondent: Filter = .any
    var documentType: Filter = .any
    var tags: Tag = .any

    private var query: String?
    var searchText: String? {
        get { query }
        set(value) {
            query = value == "" ? nil : value
        }
    }

    var filtering: Bool {
        return documentType != .any || correspondent != .any
    }
}

@MainActor
class DocumentStore: ObservableObject {
    @Published var documents: [Document] = []
//    @Published private(set) var isLoading = false

    @Published private(set) var correspondents: [UInt: Correspondent] = [:]
    @Published private(set) var documentTypes: [UInt: DocumentType] = [:]
    @Published private(set) var tags: [UInt: Tag] = [:]

    private var nextPage: URL?

    @Published var filterState = FilterState()

    private var thumbnailCache: OrderedDictionary<Document, UIImage> = [:]
    static let maxThumbnailCacheSize = 100

    let semaphore = AsyncSemaphore(value: 1)

    func clearDocuments() {
        documents = []
    }

    init() {
        Task {
            async let _ = await fetchAllTags()
            async let _ = await fetchAllCorrespondents()
            async let _ = await fetchAllDocumentTypes()
        }
    }

    func resetPage() {
        nextPage = Endpoint.documents(page: 1, filter: filterState).url
    }

    func updateDocument(_ document: Document) async throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        let json = try encoder.encode(document)

        var request = URLRequest.common(url: Endpoint.document(id: document.id).url!)
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

    func deleteDocument(_ document: Document) async throws {
        var request = URLRequest.common(url: Endpoint.document(id: document.id).url!)
        request.httpMethod = "DELETE"

        let (data, response) = try await URLSession.shared.data(for: request)

        if let statusCode = (response as? HTTPURLResponse)?.statusCode, statusCode != 204 {
            print("Delete document: Status was not 204 but \(statusCode)")
            print(String(data: data, encoding: .utf8)!)
            throw APIError.deleteFailed
        }

        for i in 0 ..< documents.count {
            if documents[i].id == document.id {
                documents.remove(at: i)
                break
            }
        }
    }

    func fetchDocuments(clear: Bool) async {
        await semaphore.wait()
        defer { semaphore.signal() }

        if clear {
            nextPage = Endpoint.documents(page: 1, filter: filterState).url!
//            documents = []
        }

        guard let url = nextPage else {
            print("Have no next page")
            return // no next page
        }

        guard let response = await getDocuments(url: url) else {
            return
        }

        if clear {
            documents = response.results
        } else {
            documents += response.results
        }
        nextPage = response.next
    }

    func fetchAllCorrespondents() async {
        await fetchAll(ListResponse<Correspondent>.self,
                       endpoint: Endpoint.correspondents(), collection: \.correspondents)
    }

    func fetchAllDocumentTypes() async {
        await fetchAll(ListResponse<DocumentType>.self,
                       endpoint: Endpoint.documentTypes(), collection: \.documentTypes)
    }

    func fetchAllTags() async {
        await fetchAll(ListResponse<Tag>.self,
                       endpoint: Endpoint.tags(), collection: \.tags)
    }

    func fetchAll() async {
        async let c: () = fetchAllCorrespondents()
        async let d: () = fetchAllDocumentTypes()
        async let t: () = fetchAllTags()
        _ = await (c, d, t)
    }

    private func fetchAll<T>(_ type: T.Type, endpoint: Endpoint,
                             collection: ReferenceWritableKeyPath<DocumentStore, [UInt: T.ObjectType]>) async
        where T: Decodable, T: ListResponseProtocol, T.ObjectType.ID == UInt
    {
        guard var url = endpoint.url else {
            return
        }
        while true {
            do {
                let request = URLRequest.common(url: url)
                let (data, _) = try await URLSession.shared.data(for: request)

                let decoded = try decoder.decode(type, from: data)

                for element in decoded.results {
                    self[keyPath: collection][element.id] = element
                }

                if let next = decoded.next {
                    url = next
                } else {
                    break
                }

            } catch {
                print(error)
                break
            }
        }
    }

    private func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T? {
        guard let url = URL(string: API_BASE_URL + "\(path)/\(id)/") else {
            return nil
        }

        let request = URLRequest.common(url: url)

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

    private func getSingleCached<T>(
        _ type: T.Type, id: UInt, path: String, cache: ReferenceWritableKeyPath<DocumentStore, [UInt: T]>
    ) async -> T? where T: Decodable {
        if let element = self[keyPath: cache][id] {
            return element
        }

        guard let element = await getSingle(type, id: id, path: path) else {
            return nil
        }

        self[keyPath: cache][id] = element
        return element
    }

    func getCorrespondent(id: UInt) async -> Correspondent? {
        return await getSingleCached(Correspondent.self, id: id,
                                     path: "correspondents", cache: \.correspondents)
    }

    func getDocumentType(id: UInt) async -> DocumentType? {
        return await getSingleCached(DocumentType.self, id: id,
                                     path: "document_types", cache: \.documentTypes)
    }

    func getDocument(id: UInt) async -> Document? {
        return await getSingle(Document.self, id: id, path: "documents")
    }

    func getTag(id: UInt) async -> Tag? {
        return await getSingleCached(Tag.self, id: id, path: "tags", cache: \.tags)
    }

    func getTags(_ ids: [UInt]) async -> [Tag] {
        var tags: [Tag] = []
        for id in ids {
            if let tag = await getTag(id: id) {
                tags.append(tag)
            }
        }
        return tags
    }

    func getImage(document: Document) async -> (Bool, UIImage?) {
        // @TODO: Add limited size caching
//        if let image = thumbnailCache[document] {
//            return (true, image)
//        }

        let image = await getImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/"))

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
        request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

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
