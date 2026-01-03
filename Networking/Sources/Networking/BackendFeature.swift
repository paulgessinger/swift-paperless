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

  func isSupported(on backendVersion: Version) -> Bool {
    switch self {
    case .customFieldsOnCreate:
      backendVersion >= Version(2, 19, 0)
    case .dateFilterModified, .dateFilterPreviousIntervals:
      backendVersion >= Version(2, 20, 0)
    }
  }
}
