//
//  OfflineBrowsingMode+localizedName.swift
//  swift-paperless
//

import Foundation

extension AppSettings.OfflineBrowsingMode {
  public var localizedName: String {
    switch self {
    case .recentlyBrowsed:
      String(localized: .settings(.offlineBrowsingModeRecentlyBrowsed))
    case .entireLibrary:
      String(localized: .settings(.offlineBrowsingModeEntireLibrary))
    }
  }
}
