//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation

protocol APIListResponse {
    associatedtype ObjectType: Identifiable

    var results: [ObjectType] { get }
    var next: URL? { get }
}

struct Document: Codable, Identifiable, Equatable, Hashable {
    var id: UInt
    var added: String
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
}

struct DocumentResponse: Decodable, APIListResponse {
    var count: UInt
    var next: URL?
    var previous: String?
    var results: [Document]
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

struct CorrespondentResponse: Decodable, APIListResponse {
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Correspondent]
}

struct DocumentType: Codable, Identifiable {
    var id: UInt
    var name: String
    var slug: String
}

struct DocumentTypeResponse: Decodable, APIListResponse {
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [DocumentType]
}

func authRequest(url: URL) -> URLRequest {
    var request = URLRequest(url: url)
    request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

    return request
}

enum DateDecodingError: Error {
    case invalidDate(string: String)
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
    var correspondent: UInt?
    var documentType: UInt?
    var searchText: String?
}

@MainActor
class DocumentStore: ObservableObject {
    @Published var documents: [Document] = []
//    @Published private(set) var isLoading = false

    private(set) var correspondents: [UInt: Correspondent] = [:]
    private(set) var documentTypes: [UInt: DocumentType] = [:]

    private var nextPage: URL?

    private(set) var filterState = FilterState()

    func clearDocuments() {
        documents = []
    }

    init() {
//        nextPage = Endpoint.documents(page: 1).url
        resetPage()
    }

//    func clear() {
//        documents = []
//        correspondents = [:]
//        documentTypes = [:]
//        hasNextPage = true
//        currentPage = 1
//    }

    func resetPage() {
        nextPage = Endpoint.documents(page: 1, query: filterState.searchText).url
    }

    func setFilterState(to filterState: FilterState) {
        self.filterState = filterState

        resetPage()
    }

//
//    func withLoading(action: () -> Void) {
//        isLoading = true
//        Task {
//            try await Task.sleep(for: .seconds(5))
//        }
//        action()
//        isLoading = false
//    }

    func fetchDocuments(clear: Bool) async {
//        if clear {
//            resetPage()
//        }
        guard var url = nextPage else {
            return // no next page
        }
        if clear {
            url = Endpoint.documents(page: 1, query: filterState.searchText).url!
        }

        print("get docs \(url)")
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
        await fetchAll(CorrespondentResponse.self,
                       path: "correspondents", collection: \.correspondents)
    }

    private func fetchAll<T>(_ type: T.Type, path: String,
                             collection: ReferenceWritableKeyPath<DocumentStore, [UInt: T.ObjectType]>) async
        where T: Decodable, T: APIListResponse, T.ObjectType.ID == UInt
    {
        guard var url = URL(string: API_BASE_URL + "\(path)/") else {
            return
        }
        while true {
            do {
                let request = authRequest(url: url)
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

    func fetchAllDocumentTypes() async {
        await fetchAll(DocumentTypeResponse.self,
                       path: "document_types", collection: \.documentTypes)
    }

    private func getSingle<T: Decodable>(_ type: T.Type, id: UInt, path: String) async -> T? {
        guard let url = URL(string: API_BASE_URL + "\(path)/\(id)/") else {
            return nil
        }

//        print(url)

        let request = authRequest(url: url)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if (response as? HTTPURLResponse)?.statusCode != 200 {
                print("Getting correspondent: Status was not 200")
                return nil
            }

//            print(String(decoding: data, as: UTF8.self))

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
//            print("Cached correspondent \(id) (cache size: \(self[keyPath: cache].count))")
            return element
        }

//        print("Cache size: \(self[keyPath: cache].count)")

//        print("Loading correspondent \(id)")

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
}
