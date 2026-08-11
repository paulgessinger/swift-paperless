//
//  UserPermissionsResource+localizedName.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 05.01.25.
//

import DataModel
import os

extension UserPermissions.Resource {
  public var localizedName: String {
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
    case .shareLink: String(localized: .permissions(.resourceShareLink))
    case .workflow: String(localized: .permissions(.resourceWorkflow))
    case .customField: CustomField.localizedName
    }
  }

  /// Permissions are granted per resource *type*, so prose about them reads as a
  /// class ("not allowed to delete Storage paths"), not as one instance.
  public var localizedNamePlural: String {
    switch self {
    case .document: Document.localizedNamePlural
    case .note: Document.Note.localizedNamePlural
    case .tag: Tag.localizedNamePlural
    case .correspondent: Correspondent.localizedNamePlural
    case .documentType: DocumentType.localizedNamePlural
    case .storagePath: StoragePath.localizedNamePlural
    case .savedView: SavedView.localizedNamePlural
    case .paperlessTask: PaperlessTask.localizedNamePlural
    case .uiSettings: UISettings.localizedNamePlural
    case .user: User.localizedNamePlural
    case .group: UserGroup.localizedNamePlural
    case .mailAccount: String(localized: .permissions(.resourceMailAccounts))
    case .mailRule: String(localized: .permissions(.resourceMailRules))
    case .shareLink: String(localized: .permissions(.resourceShareLinks))
    case .workflow: String(localized: .permissions(.resourceWorkflows))
    case .customField: CustomField.localizedNamePlural
    }
  }
}

extension UserPermissions.Operation {
  public var localizedName: String {
    switch self {
    case .view: String(localized: .permissions(.view))
    case .add: String(localized: .permissions(.add))
    case .change: String(localized: .permissions(.change))
    case .delete: String(localized: .permissions(.delete))
    }
  }
}
