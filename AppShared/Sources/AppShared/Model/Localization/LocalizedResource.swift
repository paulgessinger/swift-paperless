//
//  LocalizedResource.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.12.2024.
//

import DataModel
import Foundation

public protocol LocalizedResource {
  static var localizedName: String { get }
  static var localizedNamePlural: String { get }
  static var localizedNoViewPermissions: String { get }
}

extension Document: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.document)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.documents)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsDocument))
  }
}

extension Document.Note: LocalizedResource {
  public static var localizedName: String { String(localized: .documentMetadata(.note)) }
  public static var localizedNamePlural: String { String(localized: .documentMetadata(.notes)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsNotes))
  }
}

extension Tag: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.tag)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.tags)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsTags))
  }
}

extension User: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.user)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.users)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsUsers))
  }
}

extension UserGroup: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.group)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.groups)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsGroups))
  }
}

extension DocumentType: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.documentType)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.documentTypes)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsDocumentTypes))
  }
}

extension Correspondent: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.correspondent)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.correspondents)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsCorrespondents))
  }
}

extension SavedView: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.savedView)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.savedViews)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsDocument))
  }
}

extension StoragePath: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.storagePath)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.storagePaths)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsStoragePaths))
  }
}

extension PaperlessTask: LocalizedResource {
  public static var localizedName: String { String(localized: .tasks(.titleSingular)) }
  public static var localizedNamePlural: String { String(localized: .tasks(.title)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsSavedViews))
  }
}

extension UISettings: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.uiSettings)) }
  public static var localizedNamePlural: String { localizedName }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsUISettings))
  }
}

extension CustomField: LocalizedResource {
  public static var localizedName: String { String(localized: .localizable(.customField)) }
  public static var localizedNamePlural: String { String(localized: .localizable(.customFields)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsCustomFields))
  }
}
