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
  public static var localizedName: String { String(localized: .app(.document)) }
  public static var localizedNamePlural: String { String(localized: .app(.documents)) }

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
  public static var localizedName: String { String(localized: .app(.tag)) }
  public static var localizedNamePlural: String { String(localized: .app(.tags)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsTags))
  }
}

extension User: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.user)) }
  public static var localizedNamePlural: String { String(localized: .app(.users)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsUsers))
  }
}

extension UserGroup: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.group)) }
  public static var localizedNamePlural: String { String(localized: .app(.groups)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsGroups))
  }
}

extension DocumentType: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.documentType)) }
  public static var localizedNamePlural: String { String(localized: .app(.documentTypes)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsDocumentTypes))
  }
}

extension Correspondent: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.correspondent)) }
  public static var localizedNamePlural: String { String(localized: .app(.correspondents)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsCorrespondents))
  }
}

extension SavedView: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.savedView)) }
  public static var localizedNamePlural: String { String(localized: .app(.savedViews)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsDocument))
  }
}

extension StoragePath: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.storagePath)) }
  public static var localizedNamePlural: String { String(localized: .app(.storagePaths)) }

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
  public static var localizedName: String { String(localized: .app(.uiSettings)) }
  public static var localizedNamePlural: String { localizedName }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsUISettings))
  }
}

extension CustomField: LocalizedResource {
  public static var localizedName: String { String(localized: .app(.customField)) }
  public static var localizedNamePlural: String { String(localized: .app(.customFields)) }

  public static var localizedNoViewPermissions: String {
    String(localized: .permissions(.noViewPermissionsCustomFields))
  }
}
