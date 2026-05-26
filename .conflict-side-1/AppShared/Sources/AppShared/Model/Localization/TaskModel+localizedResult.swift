//
//  TaskModel+localizedResult.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.12.24.
//

import DataModel

extension PaperlessTask {
  public var localizedResult: String? {
    switch resultKind {
    case .empty:
      nil
    case .duplicate(let fileName):
      String(
        localized: .tasks(.errorDuplicate(fileName ?? String(localized: .tasks(.unknownFileName)))))
    case .raw(let message):
      message
    }
  }
}
