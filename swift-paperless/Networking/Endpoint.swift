//
//  Endpoint.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import Foundation

struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }
}

extension Endpoint {
    static func documents(page: UInt, filter: FilterState = FilterState(), pageSize: UInt = 100) -> Endpoint {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "truncate_content", value: "true"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]

        let rules = filter.rules
        queryItems += FilterRule.queryItems(for: rules)

        var ordering: String = filter.sortField.rawValue
        if filter.sortOrder.reverse {
            ordering = "-" + ordering
        }

        queryItems.append(.init(name: "ordering", value: ordering))

        return Endpoint(
            path: "/api/documents/",
            queryItems: queryItems
        )
    }

    static func document(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(id)/", queryItems: [])
    }

    static func thumbnail(documentId: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(documentId)/thumb/", queryItems: [])
    }

    static func download(documentId: UInt) -> Endpoint {
        return Endpoint(path: "/api/documents/\(documentId)/download/", queryItems: [])
    }

    static func searchAutocomplete(term: String, limit: UInt = 10) -> Endpoint {
        return Endpoint(
            path: "/api/search/autocomplete/",
            queryItems: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func correspondents() -> Endpoint {
        return Endpoint(path: "/api/correspondents/",
                        queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createCorrespondent() -> Endpoint {
        return Endpoint(path: "/api/correspondents/")
    }

    static func correspondent(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/correspondents/\(id)/")
    }

    static func documentTypes() -> Endpoint {
        return Endpoint(path: "/api/document_types/", queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createDocumentType() -> Endpoint {
        return Endpoint(path: "/api/document_types/")
    }

    static func documentType(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/document_types/\(id)/")
    }

    static func tags() -> Endpoint {
        return Endpoint(path: "/api/tags/", queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createTag() -> Endpoint {
        return Endpoint(path: "/api/tags/", queryItems: [])
    }

    static func tag(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/tags/\(id)/")
    }

    static func createDocument() -> Endpoint {
        return Endpoint(path: "/api/documents/post_document/", queryItems: [])
    }

    static func listAll<T>(_ type: T.Type) -> Endpoint where T: Model {
        switch type {
        case is Correspondent.Type:
            return correspondents()
        case is DocumentType.Type:
            return documentTypes()
        case is Tag.Type:
            return tags()
        case is Document.Type:
            return documents(page: 1, filter: FilterState())
        case is SavedView.Type:
            return savedViews()
        case is StoragePath.Type:
            return storagePaths()
        default:
            fatalError("Invalid type")
        }
    }

    static func savedViews() -> Endpoint {
        return Endpoint(path: "/api/saved_views/",
                        queryItems: [URLQueryItem(name: "page_size", value: String(100000))])
    }

    static func createSavedView() -> Endpoint {
        return Endpoint(path: "/api/saved_views/",
                        queryItems: [])
    }

    static func savedView(id: UInt) -> Endpoint {
        return Endpoint(path: "/api/saved_views/\(id)/",
                        queryItems: [])
    }

    static func storagePaths() -> Endpoint {
        return .init(path: "/api/storage_paths/")
    }

    static func createStoragePath() -> Endpoint {
        return .init(path: "/api/storage_paths/")
    }

    static func storagePath(id: UInt) -> Endpoint {
        return .init(path: "/api/storage_paths/\(id)/")
    }

    static func single<T>(_ type: T.Type, id: UInt) -> Endpoint where T: Model {
        var segment = ""
        switch type {
        case is Correspondent.Type:
            segment = "correspondents"
        case is DocumentType.Type:
            segment = "document_types"
        case is Tag.Type:
            segment = "tags"
        case is Document.Type:
            return document(id: id)
        case is SavedView.Type:
            segment = "saved_views"
        case is StoragePath.Type:
            segment = "storage_paths"
        default:
            fatalError("Invalid type")
        }

        return Endpoint(path: "/api/\(segment)/\(id)/",
                        queryItems: [])
    }

    func url(host: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}
