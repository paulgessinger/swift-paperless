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
        case .document: Document.localizedName
        case .note: Document.Note.localizedName
        case .tag: Tag.localizedName
        case .correspondent: Correspondent.localizedName
        case .documentType: DocumentType.localizedName
        case .storagePath: StoragePath.localizedName
        case .savedView: SavedView.localizedName
        case .paperlessTask: PaperlessTask.localizedName
        case .uiSettings: UISettings.localizedName
        case .user: User.localizedName
        case .group: UserGroup.localizedName
        case .mailAccount: String(localized: .permissions(.resourceMailAccount))
        case .mailRule: String(localized: .permissions(.resourceMailRule))
        case .history: String(localized: .permissions(.resourceHistory))
        case .appConfig: String(localized: .permissions(.resourceAppConfig))
        case .shareLink: String(localized: .permissions(.resourceShareLink))
        case .workflow: String(localized: .permissions(.resourceWorkflow))
        case .customField: String(localized: .permissions(.resourceCustomField))
        }
    }
}

extension UserPermissions.Operation {
    var localizedName: String {
        switch self {
        case .view: String(localized: .permissions(.view))
        case .add: String(localized: .permissions(.add))
        case .change: String(localized: .permissions(.change))
        case .delete: String(localized: .permissions(.delete))
        }
    }
}
