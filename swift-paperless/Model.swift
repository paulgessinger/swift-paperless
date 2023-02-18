//
//  Model.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import Foundation

struct Document: Codable, Identifiable, Equatable, Hashable {
    var id: UInt
    var added: String
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
}

struct DocumentResponse: Decodable {
    var count: UInt
    var next: String?
    var previous: String?
    var results: [Document]
}

struct Correspondent: Codable {
    var id: UInt
    var documentCount: UInt
    var isInsensitive: Bool
    var lastCorrespondence: Date?
    // match?
    var name: String
    var slug: String
}

struct CorrespondentResponse: Decodable {
    var count: UInt
    var next: URL?
    var previous: URL?
    var results: [Correspondent]
}

@MainActor
class DocumentStore: ObservableObject {
    @Published var documents: [Document] = []
    @Published private(set) var isLoading = false

    @Published var correspondents: [UInt: Correspondent] = [:]

    private var hasNextPage = true
    private(set) var currentPage: UInt = 1

    func fetchDocuments() async {
        if !hasNextPage { return }

        isLoading = true
        guard let response = await getDocuments(page: currentPage) else {
            return
        }

        documents += response.results

        if response.next != nil {
            currentPage += 1
        } else {
            hasNextPage = false
        }

        isLoading = false
    }

    func fetchCorrespondents() async {
        guard var url = URL(string: API_BASE_URL + "correspondents/") else {
            return
        }
        while true {
            do {
                var request = URLRequest(url: url)
                request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")
                let (data, _) = try await URLSession.shared.data(for: request)

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let decoded = try decoder.decode(CorrespondentResponse.self, from: data)

                for c in decoded.results {
                    correspondents[c.id] = c
                }

                if let next = decoded.next {
                    url = next
                } else {
                    break
                }

            } catch { print(error)
                break
            }
        }
    }
}
