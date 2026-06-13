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
    case .fill:
      String(localized: .settings(.transferCategoryFill))
    case .reconcile:
      String(localized: .settings(.transferCategoryReconcile))
    case .other:
      String(localized: .settings(.transferCategoryOther))
    }
  }
}
