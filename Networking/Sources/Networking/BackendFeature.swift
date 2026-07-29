//
//  BackendFeatures.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 01.01.26.
//

import Common

public enum BackendFeature {
  // Dedicated next ASN endpoint / 2.0.0
  case nextAsnEndpoint

  // Dedicated tasks acknowledge endpoint / 2.14.0
  case taskAcknowledgeEndpoint

  // https://github.com/paperless-ngx/paperless-ngx/pull/10859 / 2.19.0
  case customFieldsOnCreate

  // https://github.com/paperless-ngx/paperless-ngx/pull/11411 / 2.20.0
  case dateFilterPreviousIntervals
  case dateFilterModified

  // https://github.com/paperless-ngx/paperless-ngx/pull/12142 / API v10, likely v3.0.0
  case savedViewNewVisibility

  // https://github.com/paperless-ngx/paperless-ngx/pull/12142 / API v10, likely v3.0.0
  case savedViewPermissions

  // https://github.com/paperless-ngx/paperless-ngx/pull/12584 / API v10, likely v3.0.0
  // Task list / detail endpoint wire shape: v10 wraps list responses in the
  // standard ListResponse envelope; older backends return a top-level array.
  case taskListEnvelope

  // https://github.com/paperless-ngx/paperless-ngx/pull/11884 / API v10, 3.0.0
  // Tantivy-backed `text` document filter parameter, which supersedes the
  // deprecated `title_content`. Older backends silently ignore unknown query
  // parameters, so sending `text` there would return every document instead of
  // the search results — this must stay gated.
  case tantivySimpleSearch

  func isSupported(on backendVersion: Version, api apiVersion: UInt) -> Bool {
    switch self {
    case .nextAsnEndpoint:
      backendVersion >= Version(2, 0, 0)
    case .taskAcknowledgeEndpoint:
      backendVersion >= Version(2, 14, 0)
    case .customFieldsOnCreate:
      backendVersion >= Version(2, 19, 0)
    case .dateFilterModified, .dateFilterPreviousIntervals:
      backendVersion >= Version(2, 20, 0)
    case .savedViewNewVisibility, .savedViewPermissions, .taskListEnvelope, .tantivySimpleSearch:
      apiVersion >= 10 || backendVersion >= Version(3, 0, 0)
    }
  }
}
