//
//  UserPermissionsResource+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.25.
//

import DataModel

extension UserPermissions.Resource {
    var localizedName: String {
        switch self {
        case .document: Document.localizedName
        case .tag: Tag.localizedName
        case .correspondent: Correspondent.localizedName
        case .documentType: DocumentType.localizedName
        case .storagePath: StoragePath.localizedName
        case .savedView: SavedView.localizedName
        case .paperlessTask: PaperlessTask.localizedName
        case .uiSettings: UISettings.localizedName
        case .user: User.localizedName
        case .group: UserGroup.localizedName
        default: rawValue
        }
    }
}
