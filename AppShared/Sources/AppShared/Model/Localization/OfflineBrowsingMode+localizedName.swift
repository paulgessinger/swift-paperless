//
//  OfflineBrowsingMode+localizedName.swift
//  swift-paperless
//

import Foundation

extension OfflineBrowsingMode {
  public var localizedName: String {
    switch self {
    case .recentlyBrowsed:
      String(localized: .settings(.offlineBrowsingModeRecentlyBrowsed))
    case .entireLibrary:
      String(localized: .settings(.offlineBrowsingModeEntireLibrary))
    }
  }
}
