//
//  Endpoint.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import DataModel
import Foundation
import os

public struct Endpoint {
    public let path: String
    public let queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }
}

public extension Endpoint {
    static func root() -> Endpoint {
        Endpoint(path: "/api", queryItems: [])
    }

    static let defaultDocumentPageSize: UInt = 250

    static func documents(page: UInt, filter: FilterState, pageSize: UInt = Self.defaultDocumentPageSize) -> Endpoint {
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

    static func document(id: UInt, fullPerms: Bool = true) -> Endpoint {
        var queryItems: [URLQueryItem] = []

        if fullPerms {
            queryItems.append(URLQueryItem(name: "full_perms", value: "true"))
        }

        return Endpoint(path: "/api/documents/\(id)",
                        queryItems: queryItems)
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
        Endpoint(path: "/api/storage_paths",
                 queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func createStoragePath() -> Endpoint {
        Endpoint(path: "/api/storage_paths")
    }

    static func storagePath(id: UInt) -> Endpoint {
        Endpoint(path: "/api/storage_paths/\(id)")
    }

    static func users() -> Endpoint {
        Endpoint(path: "/api/users",
                 queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func groups() -> Endpoint {
        Endpoint(path: "/api/groups",
                 queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func uiSettings() -> Endpoint {
        Endpoint(path: "/api/ui_settings")
    }

    static func tasks(name: TaskName? = nil, acknowledged: Bool = false) -> Endpoint {
        var queryItems: [URLQueryItem] = []
        if let name {
            queryItems.append(URLQueryItem(name: "task_name", value: name.rawValue))
        }
        queryItems.append(URLQueryItem(name: "acknowledged", value: acknowledged ? "true" : "false"))
        return Endpoint(path: "/api/tasks", queryItems: queryItems)
    }

    static func task(id: UInt) -> Endpoint {
        Endpoint(path: "/api/tasks/\(id)")
    }

    static func acknowlegdeTasksV1() -> Endpoint {
        Endpoint(path: "/api/acknowledge_tasks")
    }

    // https://github.com/paperless-ngx/paperless-ngx/pull/8195
    static func acknowlegdeTasks() -> Endpoint {
        Endpoint(path: "/api/tasks/acknowledge")
    }

    static func customFields() -> Endpoint {
        Endpoint(path: "/api/custom_fields", queryItems: [URLQueryItem(name: "page_size", value: String(100_000))])
    }

    static func appConfiguration() -> Endpoint {
        Endpoint(path: "/api/config")
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
            Logger.networking.error("URL component decomposition for endpoint building failed")
            return nil
        }
        // Remove trailing slashes from the path
        components.path = components.path.replacingOccurrences(of: "/$", with: "")
        if components.url == nil {
            Logger.networking.error("URL trailing slash removal for endpoint building failed")
            return nil
        }
        var result = components.url!.appending(path: path, directoryHint: .isDirectory)
        if !queryItems.isEmpty {
            result.append(queryItems: queryItems)
        }
        Logger.networking.trace("URL for Endpoint \(path): \(result)")
        return result
    }
}
