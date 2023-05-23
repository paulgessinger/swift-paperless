//
//  DocumentModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.05.23.
//

import Foundation

protocol DocumentProtocol: Codable {
    var documentType: UInt? { get set }
    var correspondent: UInt? { get set }
    var tags: [UInt] { get set }
    var storagePath: UInt? { get set }
}

struct Document: Identifiable, Equatable, Hashable, Model, DocumentProtocol {
    var id: UInt
    var title: String
    var documentType: UInt?
    var correspondent: UInt?
    var created: Date
    var tags: [UInt]

    private(set) var added: String? = nil
    var storagePath: UInt? = nil

    private enum CodingKeys: String, CodingKey {
        case id, title
        case documentType = "document_type"
        case correspondent, created, tags, added
        case storagePath = "storage_path"
    }
}

struct ProtoDocument: DocumentProtocol {
    var title: String = ""
    var documentType: UInt? = nil
    var correspondent: UInt? = nil
    var tags: [UInt] = []
    var created: Date = .now
    var storagePath: UInt? = nil
}
