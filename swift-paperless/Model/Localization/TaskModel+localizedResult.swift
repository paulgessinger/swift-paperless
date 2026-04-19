//
//  TaskModel+localizedResult.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.12.24.
//

import DataModel

extension PaperlessTask {
  var localizedResult: String? {
    guard let result else {
      return nil
    }

    if duplicateDocumentId != nil {
      let fileName = taskFileName ?? String(localized: .tasks(.unknownFileName))
      return String(localized: .tasks(.errorDuplicate(fileName)))
    }

    return String(stringLiteral: result)
  }
}
