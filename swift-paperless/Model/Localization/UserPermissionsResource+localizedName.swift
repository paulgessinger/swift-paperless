//
//  UserPermissionsResource+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.25.
//

import DataModel
import os

extension UserPermissions.Resource {
    var localizedName: String {
        switch self {
        case .document: return Document.localizedName
        case .note: return Document.Note.localizedName
        case .tag: return Tag.localizedName
        case .correspondent: return Correspondent.localizedName
        case .documentType: return DocumentType.localizedName
        case .storagePath: return StoragePath.localizedName
        case .savedView: return SavedView.localizedName
        case .paperlessTask: return PaperlessTask.localizedName
        case .uiSettings: return UISettings.localizedName
        case .user: return User.localizedName
        case .group: return UserGroup.localizedName
        default:
            Logger.shared.warning("Localized name for unknown resource \(rawValue, privacy: .public) requested")
            return rawValue
        }
    }
}
