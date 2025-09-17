//
//  LoginStage.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import SwiftUI

enum LoginStage: CaseIterable, Comparable {
  case connection
  case credentials

  var label: Text {
    switch self {
    case .connection:
      Text("1. ") + Text(.login(.stageConnection))
    case .credentials:
      Text("2. ") + Text(.login(.stageCredentials))
    }
  }
}
