//
//  Utilities.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Combine
import Foundation
import SwiftUI

class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var tasks = Set<AnyCancellable>()

    init(delay: TimeInterval = 0.5) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &tasks)
    }
}

extension Text {
    static func titleCorrespondent(value: Correspondent?) -> Text {
        if let correspondent = value {
            return Text("\(correspondent.name): ").bold().foregroundColor(.blue)
        }
        else {
            return Text("")
        }
    }

    static func titleDocumentType(value: DocumentType?) -> Text {
        if let documentType = value {
            return Text("\(documentType.name)").bold().foregroundColor(.orange)
        }
        else {
            return Text("")
        }
    }
}
