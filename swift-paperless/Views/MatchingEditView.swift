//
//  MatchingEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 23.04.23.
//

import Foundation
import SwiftUI

struct MatchEditView<Element>: View where Element: MatchingModel {
    @Binding var element: Element

    @State private var showTextField = false

    var body: some View {
        Group {
            Section("Matching") {
                Picker("Matching algorithm", selection: $element.matchingAlgorithm) {
                    ForEach(MatchingAlgorithm.allCases, id: \.self) { alg in
                        Text("\(alg.title)").tag(alg)
                    }
                }

                VStack {
                    Text("\(element.matchingAlgorithm.label)")
                        .id(element.matchingAlgorithm)
                        .foregroundColor(.gray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .animation(.linear, value: element.matchingAlgorithm)
            }

            if showTextField {
                TextField("Matching pattern", text: $element.match)
                    .clearable($element.match)

                Toggle("Case insensitive", isOn: $element.isInsensitive)
            }
        }
        .onChange(of: element.matchingAlgorithm) { value in
            withAnimation {
                switch value {
                case .auto, .none:
                    showTextField = false
                default:
                    showTextField = true
                }
            }
        }
    }
}
