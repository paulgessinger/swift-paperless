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

private struct IconBox<ID: Hashable>: View {
    @Environment(DocumentDetailModel.self) private var viewModel
    @EnvironmentObject private var store: DocumentStore

    let animation: Namespace.ID
    let id: ID
    let iconId: ID
    let icon: String
    let color: Color
    let label: String

    var body: some View {
        Box(animation: animation, id: id, color: color) {
            HStack {
                Label(label, systemImage: icon)
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .matchedGeometryEffect(id: iconId, in: animation, isSource: true)
                Text(label)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
//                Label("Edit", systemImage: "pencil.circle.fill")
//                    .labelStyle(.iconOnly)
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
            label: label
        )
        .onTapGesture {
            viewModel.startEditing(editMode)
        }
        .zIndex(viewModel.zIndexActive == editMode ? 1 : 0)
    }
}

struct DocumentDetailViewV2: View {
//

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

    private struct CreatedPicker: View {
        @Bindable var viewModel: DocumentDetailModel
        @Binding var date: Date
        let animation: Namespace.ID

        @State private var showInterface = false

        @MainActor
        private func close() async {
            showInterface = false
            try? await Task.sleep(for: .seconds(0.3))
            await viewModel.stopEditing()
        }

        var body: some View {
            ScrollView(.vertical) {
                VStack {
                    DatePicker(String(localized: .localizable.documentEditCreatedDateLabel),
                               selection: $date,
                               displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .padding(.horizontal)
                        .opacity(showInterface ? 1 : 0)
                        .id(date)
                }
                .animation(.default.delay(showInterface ? 0.15 : 0), value: showInterface)

                .task {
                    try? await Task.sleep(for: .seconds(0.15))
                    showInterface = true
                }

                .onChange(of: date) {
                    Task {
                        Haptics.shared.impact(style: .light)
                        try? await Task.sleep(for: .seconds(0.3))
                        await close()
                    }
                }
            }
            .safeAreaInset(edge: .top) {
//                VStack {
                PickerHeader(color: .paletteBlue,
                             showInterface: $showInterface,
                             animation: animation,
                             id: "EditCreated",
                             closeInline: true)
                {
                    HStack {
                        Label(localized: .localizable.documentEditCreatedDateLabel, systemImage: "calendar")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                            .matchedGeometryEffect(id: "EditCreatedIcon", in: animation, isSource: true)
                        Text(.localizable.documentEditCreatedDateLabel)
                            .opacity(showInterface ? 1 : 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                } onClose: {
                    Task {
                        Haptics.shared.impact(style: .light)
                        await close()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
//                }
            }
        }
    }

    var body: some View {
        Group {
            editingView

            VStack {
                if viewModel.editMode == .none || viewModel.editMode == .closing {
                    ScrollView(.vertical) {
                        VStack {
                            Text(viewModel.document.title)
                                .font(.title)
                                .bold()
                                .frame(maxWidth: .infinity, alignment: .leading)
                            LazyVGrid(columns: [GridItem(), GridItem()]) {
                                CommonBox(DocumentType.self, animation: animation)
                                CommonBox(Correspondent.self, animation: animation)
                                CommonBox(StoragePath.self, animation: animation)

                                IconBox(animation: animation,
                                        id: "EditCreated",
                                        iconId: "EditCreatedIcon",
                                        icon: "calendar",
                                        color: .paletteBlue,
                                        label: DocumentCell.dateFormatter.string(from: viewModel.document.created))
                                    .onTapGesture {
                                        viewModel.startEditing(.created)
                                    }
                                    .zIndex(viewModel.zIndexActive == .created ? 1 : 0)

//                                DatePicker(selection: $viewModel.document.created.animation(.default),
//                                           displayedComponents: .date) {
                                ////                                    Text("HI")
//                                }
//                                           .labelsHidden()
//                                           .datePickerStyle(.graphical)

//                                Box(animation: animation, id: "EditCreated", color: .paletteBlue) {
//                                    HStack {
//                                        Label(localized: .localizable.documentEditCreatedDateLabel, systemImage: "calendar")
//                                            .labelStyle(.iconOnly)
//                                            .font(.title3)
//
//                                        Text(DocumentCell.dateFormatter.string(from: viewModel.document.created))
//                                    }
//                                }

                                Text("Other")
                                Text("Stuff")
                            }
                        }
                        .padding()
                    }

                    .safeAreaInset(edge: .bottom) {
                        VStack {
                            if viewModel.download == .loading {
                                HStack(spacing: 5) {
                                    ProgressView()
                                    Text(.localizable.loading)
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
            DocumentDetailPreviewWrapper(state: $viewModel.download)
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
            await viewModel.loadDocument()
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

// MARK: - Previews

#Preview("DocumentDetailsView") {
    PreviewHelper()
}
