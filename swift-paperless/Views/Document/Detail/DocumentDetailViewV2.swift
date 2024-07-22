//
//  DocumentDetailViewV2.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import NukeUI
import os
import SwiftUI

private struct Box<Content: View, ID: Hashable>: View {
    @Environment(DocumentDetailModel.self) private var viewModel
//    @Bindable var viewModel: DocumentDetailModel

    let animation: Namespace.ID
    let id: ID
    let color: Color
    @ViewBuilder let label: () -> Content

    var body: some View {
        HStack {
            label()
        }
        .foregroundStyle(.white)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        .background {
            RoundedRectangle(cornerRadius: 25, style: .continuous)
                .fill(color)
                .matchedGeometryEffect(id: id, in: animation, isSource: true)
        }
    }
}

private struct IconBox<Content: View, ID: Hashable>: View {
    @Environment(DocumentDetailModel.self) private var viewModel
    @EnvironmentObject private var store: DocumentStore

    let animation: Namespace.ID
    let id: ID
    let iconId: ID
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        Box(animation: animation, id: id, color: color) {
            HStack {
                Label {
                    content()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                } icon: {
                    Image(systemName: icon)
                        .font(.title3)
                        .matchedGeometryEffect(id: iconId, in: animation, isSource: true)
                }
            }
        }
    }
}

private struct CommonBox<Element>: View where Element: Pickable {
    @Environment(DocumentDetailModel.self) private var viewModel
    @EnvironmentObject private var store: DocumentStore

    let animation: Namespace.ID

    private let editMode: DocumentDetailModel.EditMode

    init(_: Element.Type, animation: Namespace.ID) {
        self.animation = animation

        editMode = switch Element.self {
        case is Correspondent.Type: .correspondent
        case is DocumentType.Type: .documentType
        case is StoragePath.Type: .storagePath
        default:
            fatalError("Unknown element \(Element.self)")
        }
    }

    private var suggestionsKey: KeyPath<Suggestions, [UInt]> {
        switch Element.self {
        case is Correspondent.Type: \.correspondents
        case is DocumentType.Type: \.documentTypes
        case is StoragePath.Type: \.storagePaths
        default:
            fatalError("Unknown element \(Element.self)")
        }
    }

    @ViewBuilder
    private var suggestions: some View {
        let _ = print("Render SUGGESTIONS")
        if let suggestions = viewModel.suggestions {
            let names = suggestions[keyPath: suggestionsKey]
                .filter { viewModel.document[keyPath: Element.documentPath(Document.self)] != $0 }
                .compactMap { viewModel.store[keyPath: Element.storePath][$0]?.name }
            let _ = print(names)
            ForEach(names, id: \.self) { name in
                Text(name)
            }
        }
    }

    var body: some View {
        let path = Element.documentPath(Document.self)
        let label = if let id = viewModel.document[keyPath: path], let name = store[keyPath: Element.storePath][id]?.name {
            name
        } else {
            Element.notAssignedPicker
        }
        IconBox(
            animation: animation,
            id: "Edit\(Element.self)",
            iconId: "EditIcon\(Element.self)",
            icon: Element.icon,
            color: editMode.color,
            content: {
//                VStack(alignment: .trailing) {
                Text(label)
//                    HStack{ suggestions }
//                        .font(.caption)
//                }
            }
        )
        .onTapGesture {
            viewModel.startEditing(editMode)
        }
        .zIndex(viewModel.zIndexActive == editMode ? 1 : 0)
    }
}

@MainActor
struct DocumentDetailViewV2: DocumentDetailViewProtocol {
    typealias CreatedPicker = DocumentDetailViewV2CreatedPicker

    @ObservedObject var store: DocumentStore
    var navPath: Binding<NavigationPath>?

    @State private var previewUrl: URL?

    @State private var viewModel: DocumentDetailModel

    @EnvironmentObject private var errorController: ErrorController

    private static let bottomPadding: CGFloat = 100

    @Namespace private var animation

    private let delay = 0.1
    private let openDuration = 0.3
    private let closeDuration = 0.3

    init(store: DocumentStore,
         document: Document,
         navPath: Binding<NavigationPath>? = nil)
    {
        self.store = store
        _viewModel = State(initialValue: DocumentDetailModel(store: store,
                                                             document: document))
        self.navPath = navPath
    }

    private func makeCommonPicker<Element: Pickable>(_: Element.Type) -> some View {
        DocumentDetailCommonPicker<Element>(
            animation: animation,
            viewModel: viewModel
        )
    }

    private var editingView: some View {
        VStack {
            switch viewModel.editMode {
            case .correspondent:
                makeCommonPicker(Correspondent.self)
            case .documentType:
                makeCommonPicker(DocumentType.self)
            case .storagePath:
                makeCommonPicker(StoragePath.self)
            case .created:
                CreatedPicker(viewModel: viewModel,
                              date: $viewModel.document.created,
                              animation: animation)
            default:
                EmptyView()
            }
        }
        .id(viewModel.editingViewId)
        .animation(.spring(duration: openDuration, bounce: 0.1), value: viewModel.editMode)
    }

    private var defaultView: some View {
        ScrollView(.vertical) {
            VStack {
                Text(viewModel.document.title)
                    .font(.title)
                    .bold()
                    .frame(maxWidth: .infinity, alignment: .leading)
                CommonBox(DocumentType.self, animation: animation)
                CommonBox(Correspondent.self, animation: animation)
                CommonBox(StoragePath.self, animation: animation)
                //                LazyVGrid(columns: [GridItem(), GridItem()]) {}
                HStack {
                    VStack {
                        IconBox(animation: animation,
                                id: "EditAsn",
                                iconId: "EditAsnIcon",
                                icon: "qrcode",
                                color: .gray,
                                content: {
                                    HStack {
                                        TextField(String(localized: .localizable(.asn)),
                                                  text: $asnText, prompt: Text(String("")))
                                            .focused($asnFocused)
                                            .keyboardType(.numberPad)
                                            .overlay(alignment: .trailing) {
                                                VStack {
                                                    if asnText.isEmpty, !asnFocused {
                                                        Text("      ")
                                                            .redacted(reason: .placeholder)
                                                            .allowsHitTesting(false)
                                                    }
                                                }
                                                .animation(.default, value: asnText)
                                                .animation(.default, value: asnFocused)
                                            }

                                        Label("Save", systemImage: "checkmark.circle.fill")
                                            .labelStyle(.iconOnly)
                                    }
                                })
                    }
                    VStack {
                        IconBox(animation: animation,
                                id: "EditCreated",
                                iconId: "EditCreatedIcon",
                                icon: "calendar",
                                color: .paletteBlue,
                                content: {
                                    Text(DocumentCell.dateFormatter.string(from: viewModel.document.created))
                                })
                                .onTapGesture {
                                    viewModel.startEditing(.created)
                                }
                                .zIndex(viewModel.zIndexActive == .created ? 1 : 0)
                    }
                }
            }
        }
        .padding()
    }

    @State private var asnText: String = ""
    @FocusState private var asnFocused: Bool

    var body: some View {
        Group {
            editingView

            VStack {
                if viewModel.editMode == .none || viewModel.editMode == .closing {
                    defaultView
                        .safeAreaInset(edge: .bottom) {
                            VStack {
                                if viewModel.download == .loading {
                                    HStack(spacing: 5) {
                                        ProgressView()
                                        Text(.localizable(.loading))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical)
                                    .background(
                                        RoundedRectangle(cornerRadius: 25.0, style: .continuous)
                                            .fill(.thickMaterial)
                                    )
                                    .padding(.horizontal)
                                    .transition(
                                        .move(edge: .bottom).combined(with: .opacity))
                                }
                            }
                            .animation(.default, value: viewModel.download)
                        }
                }
            }
            .animation(.spring(duration: openDuration, bounce: 0.1), value: viewModel.editMode)
        }

        .environment(viewModel)

        .navigationBarTitleDisplayMode(.inline)

        .sheet(isPresented: $viewModel.showPreviewSheet) {
            DocumentDetailPreviewWrapper(viewModel: viewModel)
                .presentationDetents(Set(DocumentDetailModel.previewDetents), selection: $viewModel.detent)
                .presentationBackgroundInteraction(
                    .enabled(upThrough: .medium)
                )
                .interactiveDismissDisabled()
        }

        // @TODO: Do I need this anymore?
        .onChange(of: store.documents) {
            if let document = store.documents[viewModel.document.id] {
                viewModel.document = document
            }
        }

        .task {
            async let doc: () = viewModel.loadDocument()
            do {
                try await viewModel.loadSuggestions()
            } catch {
                // Should we surface this error at all?
                Logger.shared.error("Unable to get suggestions: \(error)")
            }

            await doc
        }

        .onChange(of: viewModel.document) {
            // @TODO: Handle error
            Task { try? await viewModel.saveDocument() }
        }
    }
}

// MARK: - Previews

private struct PreviewHelper: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository(downloadDelay: 3.0))
    @StateObject var errorController = ErrorController()

    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        NavigationStack {
            VStack {
                if let document {
                    DocumentDetailViewV2(store: store, document: document, navPath: $navPath)
                }
            }
            .task {
                document = try? await store.document(id: 1)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {}
                }
            }
        }
        .environmentObject(store)
        .environmentObject(errorController)

        .task {
            try? await store.fetchAll()
        }
    }
}

#Preview("DocumentDetailsView") {
    PreviewHelper()
}
