//
//  DocumentDetailCommonPicker.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import Foundation
import SwiftUI

struct PickerHeader<Content: View, ID: Hashable>: View {
    let color: Color
    @Binding var showInterface: Bool
    let animation: Namespace.ID
    let id: ID
    let closeInline: Bool

    @ViewBuilder var content: () -> Content

    let icon: String

    var onClose: (() -> Void)?

    init(color: Color,
         showInterface: Binding<Bool>,
         animation: Namespace.ID,
         id: ID,
         closeInline: Bool = false,
         icon: String = "xmark",
         content: @escaping () -> Content,
         onClose: (() -> Void)? = nil)
    {
        self.color = color
        _showInterface = showInterface
        self.animation = animation
        self.id = id
        self.closeInline = closeInline
        self.content = content
        self.onClose = onClose
        self.icon = icon
    }

    private var closeButton: some View {
        Label(localized: .localizable(.done), systemImage: icon)
            .labelStyle(.iconOnly)
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(.white)
            .frame(minWidth: 35, minHeight: 35)
            .background(Circle().fill(.thinMaterial))
            .onTapGesture {
                onClose?()
            }
    }

    var body: some View {
        HStack {
            content()
            if closeInline {
                closeButton
                    .padding(.vertical, -5)
                    .opacity(showInterface ? 1 : 0)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .overlay(alignment: .topTrailing) {
            if !closeInline, showInterface {
                closeButton
                    .padding(.vertical, 10)
                    .padding(.trailing)
            }
        }
        .animation(.default.delay(showInterface ? 0.15 : 0), value: showInterface)
        .background {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .fill(color)
                .matchedGeometryEffect(id: id, in: animation, isSource: true)
        }
        .padding(.horizontal)
    }
}

struct DocumentDetailCommonPicker<Element: Pickable>: View {
    @EnvironmentObject private var store: DocumentStore

    let animation: Namespace.ID

    @Bindable var viewModel: DocumentDetailModel

    @State private var text: String = ""
    @FocusState private var searchFocus: Bool

    @State private var showInterface = false

    private var color: Color { viewModel.editMode.color }

    private var activeId: UInt? {
        viewModel.document[keyPath: Element.documentPath(Document.self)]
    }

    @ViewBuilder
    var elementList: some View {
        let elements = store[keyPath: Element.storePath].values
            .map { $0 }
            .sorted { $0.name < $1.name }
            .filter { text.isEmpty || $0.name.range(of: text, options: .caseInsensitive) != nil }

        VStack(alignment: .leading) {
            ForEach(elements, id: \.id) { element in
                let isSelected = element.id == activeId
                VStack {
                    HStack {
                        Text("\(element.name)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .multilineTextAlignment(.leading)

                        Label("Active", systemImage: "checkmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(color)
                            .font(.title3)
                            .opacity(isSelected ? 1 : 0)
                    }

                    .contentShape(Rectangle())

                    .onTapGesture {
                        searchFocus = false
                        Haptics.shared.notification(.success)
                        withAnimation(.spring) {
                            viewModel.document[keyPath: Element.documentPath(Document.self)] = element.id
                        } completion: {
                            Task { await close() }
                        }
                    }

                    //                        .background(
                    //                            RoundedRectangle(cornerRadius: 25.0, style: .continuous)
                    //                                .fill(color)
                    //                        )
                    //                        .overlay(alignment: .bottom) {
                    //                            if element.id != elements.last?.id {
                    //                                Rectangle()
                    //                                    .fill(.gray)
                    //                                    .frame(height: 0.33)
                    //                            }
                    //                        }
                    if element.id != elements.last?.id {
                        Divider()
                    }
                }
            }
        }
//        .animation(.spring, value: activeId)

        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(.gray, lineWidth: 0.33))

        .animation(.spring(duration: 0.2), value: text)
        .padding(.horizontal)
    }

    private func close() async {
        Haptics.shared.impact(style: .light)
        showInterface = false
        if searchFocus {
            searchFocus = false
            try? await Task.sleep(for: .seconds(0.2))
        }
        await viewModel.stopEditing()
    }

    var body: some View {
        ScrollView(.vertical) {
            elementList
                .padding(.bottom)
        }
        .safeAreaInset(edge: .top, alignment: .center) {
            PickerHeader(color: color, showInterface: $showInterface, animation: animation, id: "Edit\(Element.self)") {
                VStack {
                    HStack {
                        Label(Element.singularLabel, systemImage: Element.icon)
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .matchedGeometryEffect(id: "EditIcon\(Element.self)", in: animation, isSource: true)
                        Text(Element.singularLabel)
                            .opacity(showInterface ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack {
                        Label(String(localized: .localizable(.search)), systemImage: "magnifyingglass")
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
                    .animation(.default.delay(showInterface ? 0.15 : 0), value: showInterface)
                    .opacity(showInterface ? 1 : 0)
                }
            } onClose: {
                Task {
                    await close()
                }
            }
        }

        .toolbar {
            ToolbarItem(placement: .keyboard) {
                Button {
                    searchFocus = false
                } label: {
                    Label(localized: .localizable(.documentDetailPreviewTitle), systemImage: "keyboard.chevron.compact.down")
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
//            try? await Task.sleep(for: .seconds(0.15))
            showInterface = true
            try? await Task.sleep(for: .seconds(0.5))
            searchFocus = true
        }
    }
}
