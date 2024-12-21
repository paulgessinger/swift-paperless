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

        // @TODO: More sophisticated parsing of errors
        //        let fileName = taskFileName ?? String(localized: .tasks(.unknownFileName))

        //        let duplicatePattern = /(.*): Not consuming (.*): It is a duplicate of (.*) \(#(\d*)\)/

        //        if (try? duplicatePattern.wholeMatch(in: result)) != nil {
        //            return String(localized: .tasks(.errorDuplicate(fileName)))
        //        }

        return String(stringLiteral: result)
    }
}
