//
//  MatchingEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import DataModel
import Foundation
import SwiftUI

struct MatchEditView<Element>: View where Element: MatchingModel {
    @Binding var element: Element

    @Environment(\.isEnabled) private var isEnabled

    var showTextField: Bool {
        switch element.matchingAlgorithm {
        case .auto, .none:
            false
        default:
            true
        }
    }

    var body: some View {
        Section {
            Picker(String(localized: .matching(.algorithm)), selection: $element.matchingAlgorithm) {
                ForEach(MatchingAlgorithm.allCases, id: \.self) { alg in
                    Text(alg.title).tag(alg)
                }
            }
        } header: {
            Text(.matching(.title))
        } footer: {
            Text(element.matchingAlgorithm.label)
                .lineLimit(3, reservesSpace: true)
        }

        Section {
            if showTextField {
                TextField(String(localized: .matching(.pattern)), text: $element.match)
                    .if(isEnabled) {
                        $0.clearable($element.match)
                    }
                Toggle(String(localized: .matching(.caseInsensitive)), isOn: $element.isInsensitive)
            }
        }
    }
}
