//
//  LocalizedResource.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.12.2024.
//

import DataModel
import Foundation

protocol LocalizedResource {
    static var localizedName: String { get }
    static var localizedNamePlural: String { get }
}

extension Document: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.document)) }
    static var localizedNamePlural: String { String(localized: .localizable(.documents)) }
}

extension Tag: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.tag)) }
    static var localizedNamePlural: String { String(localized: .localizable(.tags)) }
}

extension User: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.user)) }
    static var localizedNamePlural: String { String(localized: .localizable(.users)) }
}

extension UserGroup: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.group)) }
    static var localizedNamePlural: String { String(localized: .localizable(.groups)) }
}

extension DocumentType: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.documentType)) }
    static var localizedNamePlural: String { String(localized: .localizable(.documentTypes)) }
}

extension Correspondent: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.correspondent)) }
    static var localizedNamePlural: String { String(localized: .localizable(.correspondents)) }
}

extension SavedView: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.savedView)) }
    static var localizedNamePlural: String { String(localized: .localizable(.savedViews)) }
}

extension StoragePath: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.storagePath)) }
    static var localizedNamePlural: String { String(localized: .localizable(.storagePaths)) }
}

extension PaperlessTask: LocalizedResource {
    static var localizedName: String { String(localized: .tasks(.titleSingular)) }
    static var localizedNamePlural: String { String(localized: .tasks(.title)) }
}

extension UISettings: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.uiSettings)) }
    static var localizedNamePlural: String { localizedName }
}
