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
                        .matchedGeometryEffect(id: "EditIcon", in: animation, isSource: true)
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
            }
            .padding()
            .foregroundStyle(.white)
            .overlay(alignment: .topTrailing) {
                Label(localized: .localizable.done, systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(Circle().fill(.thinMaterial))
                    .padding(10)
                    .onTapGesture {
                        Task {
                            if searchFocus {
                                searchFocus = false
                                try? await Task.sleep(for: .seconds(0.3))
                            }
                            viewModel.editMode = .none
                        }
                    }
            }
            .background {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.orange)
            }
            .matchedGeometryEffect(id: "Edit", in: animation, isSource: true)
            .padding(.horizontal)
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
            try? await Task.sleep(for: .seconds(0.3))
            searchFocus = true
        }
    }
}
