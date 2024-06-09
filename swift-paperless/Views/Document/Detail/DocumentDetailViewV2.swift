//
//  DocumentDetailViewV2.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import NukeUI
import os
import SwiftUI

struct DocumentDetailViewV2: View {
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

    init(store: DocumentStore, document: Document, navPath: Binding<NavigationPath>? = nil) {
        self.store = store
        _viewModel = State(initialValue: DocumentDetailModel(store: store, document: document))
        self.navPath = navPath
    }

    private var editingView: some View {
        VStack {
            switch viewModel.editMode {
            case .none: EmptyView()
            case .correspondent:
                DocumentDetailCommonPicker<Correspondent>(
                    animation: animation,
                    viewModel: viewModel
                )
            }
        }
        .animation(.spring(duration: openDuration, bounce: 0.1), value: viewModel.editMode)
    }

    var body: some View {
        Group {
            editingView

            VStack {
                if viewModel.editMode == .none {
                    ScrollView(.vertical) {
                        VStack {
                            Grid {
                                Text(viewModel.document.title)
                                    .font(.title)
                                    .bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .gridCellColumns(2)

                                GridRow {
                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = viewModel.document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }

                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = viewModel.document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }
                                }
                                //                                .zIndex(0)

                                GridRow {
//                                    if !editing {
                                    HStack {
                                        Label(localized: .localizable.correspondent, systemImage: "person.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)
                                            .matchedGeometryEffect(id: "EditIcon", in: animation, isSource: true)
                                        Text("I am pretty long text here")
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(.orange)
                                            .matchedGeometryEffect(id: "Edit", in: animation, isSource: !viewModel.isEditing)
                                    }

                                    .onTapGesture { viewModel.editMode = .correspondent }
//                                    }

                                    HStack {
                                        Label(localized: .localizable.documentType, systemImage: "doc.fill")
                                            .labelStyle(.iconOnly)
                                            .font(.title)

                                        if let id = viewModel.document.correspondent, let name = store.correspondents[id]?.name {
                                            Text(name)
                                        } else {
                                            Text(.localizable.correspondentNotAssignedPicker)
                                        }
                                    }
                                    .foregroundStyle(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    .background {
                                        RoundedRectangle(cornerRadius: 25, style: .continuous)
                                            .fill(Color("AccentColor"))
                                    }
                                }

                                GridRow {
                                    Text("Other")
                                    Text("Stuff")
                                }
                            }
                            .padding()
                        }
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
    }
}

// MARK: - Previews

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
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
    }
}

#Preview("DocumentDetailsView") {
    let store = DocumentStore(repository: PreviewRepository(downloadDelay: 3.0))
    @StateObject var errorController = ErrorController()

    return PreviewHelper()
        .environmentObject(store)
        .environmentObject(errorController)
}
