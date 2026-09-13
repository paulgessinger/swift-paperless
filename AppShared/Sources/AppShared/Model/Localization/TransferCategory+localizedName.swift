//
//  TransferCategory+localizedName.swift
//  swift-paperless
//

import Networking

extension TransferCategory {
  public var localizedName: String {
    switch self {
    case .sync:
      String(localized: .settings(.transferCategorySync))
    case .list:
      String(localized: .settings(.transferCategoryList))
    case .fill:
      String(localized: .settings(.transferCategoryFill))
    case .thumbnails:
      String(localized: .settings(.transferCategoryThumbnails))
    case .documents:
      String(localized: .settings(.transferCategoryDocuments))
    case .reconcile:
      String(localized: .settings(.transferCategoryReconcile))
    case .other:
      String(localized: .settings(.transferCategoryOther))
    }
  }
}
