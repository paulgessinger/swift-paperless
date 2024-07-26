//
//  Endpoint.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import Foundation
import os

struct Endpoint {
    let path: String
    let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }
}

extension Endpoint {
    static func root() -> Endpoint {
        Endpoint(path: "/api", queryItems: [])
    }

    private static let defaultDocumentPageSize: UInt = 250

    static func documents(page: UInt, filter: FilterState = FilterState(), pageSize: UInt = Self.defaultDocumentPageSize) -> Endpoint {
        let endpoint = documents(page: page, rules: filter.rules, pageSize: pageSize)

        var ordering: String = filter.sortField.rawValue
        if filter.sortOrder.reverse {
            ordering = "-" + ordering
        }

        let queryItems = endpoint.queryItems + [.init(name: "ordering", value: ordering)]

        return Endpoint(path: endpoint.path, queryItems: queryItems)
    }

    static func documents(page: UInt, rules: [FilterRule] = [], pageSize: UInt = Self.defaultDocumentPageSize) -> Endpoint {
        var queryItems = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "truncate_content", value: "true"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]

        queryItems += FilterRule.queryItems(for: rules)

        return Endpoint(
            path: "/api/documents",
            queryItems: queryItems
        )
    }

    static func document(id: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(id)", queryItems: [])
    }

    static func metadata(documentId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/metadata", queryItems: [])
    }

    static func notes(documentId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/notes", queryItems: [])
    }

    static func note(documentId: UInt, noteId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/notes",
                 queryItems: [URLQueryItem(name: "id", value: String(noteId))])
    }

    static func thumbnail(documentId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/thumb", queryItems: [])
    }

    static func download(documentId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/download", queryItems: [])
    }

    static func suggestions(documentId: UInt) -> Endpoint {
        Endpoint(path: "/api/documents/\(documentId)/suggestions", queryItems: [])
    }

    static func nextAsn() -> Endpoint {
        Endpoint(path: "/api/documents/next_asn", queryItems: [])
    }

    static func searchAutocomplete(term: String, limit: UInt = 10) -> Endpoint {
        Endpoint(
            path: "/api/search/autocomplete",
            queryItems: [
                URLQueryItem(name: "term", value: term),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func correspondents() -> Endpoint {
        Endpoint(path: "/api/correspondents",
                 queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createCorrespondent() -> Endpoint {
        Endpoint(path: "/api/correspondents")
    }

    static func correspondent(id: UInt) -> Endpoint {
        Endpoint(path: "/api/correspondents/\(id)")
    }

    static func documentTypes() -> Endpoint {
        Endpoint(path: "/api/document_types", queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createDocumentType() -> Endpoint {
        Endpoint(path: "/api/document_types")
    }

    static func documentType(id: UInt) -> Endpoint {
        Endpoint(path: "/api/document_types/\(id)")
    }

    static func tags() -> Endpoint {
        Endpoint(path: "/api/tags", queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createTag() -> Endpoint {
        Endpoint(path: "/api/tags", queryItems: [])
    }

    static func tag(id: UInt) -> Endpoint {
        Endpoint(path: "/api/tags/\(id)")
    }

    static func createDocument() -> Endpoint {
        Endpoint(path: "/api/documents/post_document", queryItems: [])
    }

    static func listAll(_ type: (some Model).Type) -> Endpoint {
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
        case is User.Type:
            return users()
        default:
            fatalError("Invalid type")
        }
    }

    static func savedViews() -> Endpoint {
        Endpoint(path: "/api/saved_views",
                 queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createSavedView() -> Endpoint {
        Endpoint(path: "/api/saved_views",
                 queryItems: [])
    }

    static func savedView(id: UInt) -> Endpoint {
        Endpoint(path: "/api/saved_views/\(id)",
                 queryItems: [])
    }

    static func storagePaths() -> Endpoint {
        .init(path: "/api/storage_paths",
              queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createStoragePath() -> Endpoint {
        .init(path: "/api/storage_paths")
    }

    static func storagePath(id: UInt) -> Endpoint {
        .init(path: "/api/storage_paths/\(id)")
    }

    static func users() -> Endpoint {
        .init(path: "/api/users",
              queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func uiSettings() -> Endpoint {
        .init(path: "/api/ui_settings")
    }

    static func tasks() -> Endpoint {
        .init(path: "/api/tasks")
    }

    static func task(id: UInt) -> Endpoint {
        .init(path: "/api/tasks/\(id)")
    }

    static func acknowlegdeTasks() -> Endpoint {
        .init(path: "/api/acknowledge_tasks")
    }

    static func single(_ type: (some Model).Type, id: UInt) -> Endpoint {
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

        return Endpoint(path: "/api/\(segment)/\(id)",
                        queryItems: [])
    }

    func url(url: URL) -> URL? {
        // Break down the URL into components
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.api.error("URL component decomposition for endpoint building failed")
            return nil
        }
        // Remove trailing slashes from the path
        components.path = components.path.replacingOccurrences(of: "/$", with: "")
        if components.url == nil {
            Logger.api.error("URL trailing slash removal for endpoint building failed")
            return nil
        }
        var result = components.url!.appending(path: path, directoryHint: .isDirectory)
        if !queryItems.isEmpty {
            result.append(queryItems: queryItems)
        }
        Logger.shared.trace("URL for Endpoint \(path): \(result)")
        return result
    }
}
