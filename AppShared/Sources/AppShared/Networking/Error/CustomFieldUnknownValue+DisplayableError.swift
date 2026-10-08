//
//  CustomFieldUnknownValue+DisplayableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.25.
//

import DataModel
import Foundation

extension CustomFieldUnknownValue: DisplayableError {
  public var message: String {
    String(localized: .customFields(.unknownValueError))
  }

  public var details: String? {
    String(localized: .customFields(.unknownValueEncode))
  }
}
