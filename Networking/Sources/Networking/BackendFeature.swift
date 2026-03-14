//
//  BackendFeatures.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.01.26.
//

import Common

public enum BackendFeature {
  // https://github.com/paperless-ngx/paperless-ngx/pull/10859 / 2.19.0
  case customFieldsOnCreate

  // https://github.com/paperless-ngx/paperless-ngx/pull/11411 / 2.20.0
  case dateFilterPreviousIntervals
  case dateFilterModified

  // https://github.com/paperless-ngx/paperless-ngx/pull/12142 / API v10, likely v3.0.0
  case savedViewNewVisibility

  // https://github.com/paperless-ngx/paperless-ngx/pull/12142 / API v10, likely v3.0.0
  case savedViewPermissions

  func isSupported(on backendVersion: Version, api apiVersion: UInt) -> Bool {
    switch self {
    case .customFieldsOnCreate:
      backendVersion >= Version(2, 19, 0)
    case .dateFilterModified, .dateFilterPreviousIntervals:
      backendVersion >= Version(2, 20, 0)
    case .savedViewNewVisibility, .savedViewPermissions:
      apiVersion >= 10 || backendVersion >= Version(3, 0, 0)
    }
  }
}
