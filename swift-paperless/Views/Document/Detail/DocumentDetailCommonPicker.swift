//
//  DocumentDetailCommonPicker.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import Foundation
import SwiftUI

struct DocumentDetailCommonPicker<Element: Pickable>: View {
    let animation: Namespace.ID

    @Bindable var viewModel: DocumentDetailModel

    @State private var text: String = ""
    @FocusState private var searchFocus: Bool

    @State private var showInterface = false

    private var color: Color {
        switch Element.self {
        case is Correspondent.Type: .paletteYellow
        case is DocumentType.Type: .paletteRed
        default: .gray
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack {
                Text("Edit \(Element.self)")
            }
        }
        .safeAreaInset(edge: .top, alignment: .center) {
            VStack {
                HStack {
                    Label(localized: .localizable.correspondent, systemImage: "person.fill")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .matchedGeometryEffect(id: "EditIcon\(Element.self)", in: animation, isSource: true)
                    Text(.localizable.correspondent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                //                        SearchBarView(text: $text)

                HStack {
                    Label(String(localized: .localizable.search), systemImage: "magnifyingglass")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .padding(.trailing, -2)
                    TextField(text: $text) {
                        Text("Search")
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .keyboardType(.alphabet)
                    .focused($searchFocus)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(.thinMaterial)
                )
                .padding(.top)
                .opacity(showInterface ? 1 : 0)
            }
            .padding()
            .foregroundStyle(.white)
            .overlay(alignment: .topTrailing) {
                if showInterface {
                    Label(localized: .localizable.done, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(.thinMaterial))
                        .padding(.vertical, 10)
                        .padding(.trailing)
                        .onTapGesture {
                            Task {
                                Haptics.shared.impact(style: .light)
                                showInterface = false
                                if searchFocus {
                                    searchFocus = false
                                    try? await Task.sleep(for: .seconds(0.3))
                                }
                                await viewModel.stopEditing()
                            }
                        }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(color)
                    .matchedGeometryEffect(id: "Edit\(Element.self)", in: animation, isSource: true)
            }
            .padding(.horizontal)
            .animation(.default, value: showInterface)
        }

        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button {
                    searchFocus = false
                } label: {
                    Label(localized: .localizable.documentDetailPreviewTitle, systemImage: "keyboard.chevron.compact.down")
                        .labelStyle(.titleAndIcon)
                }
            }
        }

        .onChange(of: searchFocus) {
            if searchFocus == true {
                viewModel.push(detent: .small)
            } else {
                viewModel.popDetent()
            }
        }

        .task {
            text = ""
            try? await Task.sleep(for: .seconds(0.15))
            showInterface = true
            try? await Task.sleep(for: .seconds(0.35))
            searchFocus = true
        }
    }
}
