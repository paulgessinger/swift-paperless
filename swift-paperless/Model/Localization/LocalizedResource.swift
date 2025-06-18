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
    static var localizedNoViewPermissions: String { get }
}

extension Document: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.document)) }
    static var localizedNamePlural: String { String(localized: .localizable(.documents)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsDocument)) }
}

extension Document.Note: LocalizedResource {
    static var localizedName: String { String(localized: .documentMetadata(.note)) }
    static var localizedNamePlural: String { String(localized: .documentMetadata(.notes)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsNotes)) }
}

extension Tag: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.tag)) }
    static var localizedNamePlural: String { String(localized: .localizable(.tags)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsTags)) }
}

extension User: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.user)) }
    static var localizedNamePlural: String { String(localized: .localizable(.users)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsUsers)) }
}

extension UserGroup: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.group)) }
    static var localizedNamePlural: String { String(localized: .localizable(.groups)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsGroups)) }
}

extension DocumentType: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.documentType)) }
    static var localizedNamePlural: String { String(localized: .localizable(.documentTypes)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsDocumentTypes)) }
}

extension Correspondent: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.correspondent)) }
    static var localizedNamePlural: String { String(localized: .localizable(.correspondents)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsCorrespondents)) }
}

extension SavedView: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.savedView)) }
    static var localizedNamePlural: String { String(localized: .localizable(.savedViews)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsDocument)) }
}

extension StoragePath: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.storagePath)) }
    static var localizedNamePlural: String { String(localized: .localizable(.storagePaths)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsStoragePaths)) }
}

extension PaperlessTask: LocalizedResource {
    static var localizedName: String { String(localized: .tasks(.titleSingular)) }
    static var localizedNamePlural: String { String(localized: .tasks(.title)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsSavedViews)) }
}

extension UISettings: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.uiSettings)) }
    static var localizedNamePlural: String { localizedName }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsUISettings)) }
}

extension CustomField: LocalizedResource {
    static var localizedName: String { String(localized: .localizable(.customField)) }
    static var localizedNamePlural: String { String(localized: .localizable(.customFields)) }

    static var localizedNoViewPermissions: String { String(localized: .permissions(.noViewPermissionsCustomFields)) }
}
