//
//  CreateDocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

struct CreateDocumentView<Title: View>: View {
    private enum Status {
        case none
        case uploading
        case complete
        case error
    }

    var sourceUrl: URL
    private var title: () -> Title

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @State private var document = ProtoDocument()
    @State private var status = Status.none

    var callback: () -> Void

    init(sourceUrl url: URL, callback: @escaping () -> Void = {}, @ViewBuilder title: @escaping () -> Title = { LogoView() }) {
        sourceUrl = url
        _document = State(initialValue: ProtoDocument(title: url.lastPathComponent))
        self.title = title
        self.callback = callback
    }

    func upload() async {
        do {
            try await store.repository.create(document: document, file: sourceUrl)
        } catch {
            errorController.push(error: error)
            status = .error
            Task {
                try? await Task.sleep(for: .seconds(3))
                status = .none
            }
            return
        }

        withAnimation {
            status = .complete
        }

        let impactMed = UIImpactFeedbackGenerator(style: .light)
        impactMed.impactOccurred()

        do {
            try await Task.sleep(for: .seconds(0.5))
        } catch {}

        callback()
    }

    var body: some View {
        NavigationStack {
            VStack {
                HStack {
                    Group {
                        PDFThumbnail(file: sourceUrl)
                            .background(.white)
                            .frame(width: 100, height: 100, alignment: .top)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.gray, lineWidth: 1))

                    Text(document.title)
                    Spacer()
                }
                .padding()
                Spacer()

                Form {
                    Section {
                        TextField(String(localized: .localizable.documentEditTitleLabel), text: $document.title) {}
                        DatePicker(String(localized: .localizable.documentEditCreatedDateLabel), selection: $document.created, displayedComponents: .date)
                    }
                    Section {
                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: CorrespondentManager.self,
                                document: $document,
                                store: store
                            )
                            .navigationTitle(String(localized: .localizable.correspondent))
                        }) {
                            HStack {
                                Text(.localizable.correspondent)
                                Spacer()
                                Group {
                                    if let id = document.correspondent {
                                        Text(store.correspondents[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable.correspondentNotAssignedPicker)
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }

                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: DocumentTypeManager.self,
                                document: $document,
                                store: store
                            )
                        }) {
                            HStack {
                                Text(.localizable.documentType)
                                Spacer()
                                Group {
                                    if let id = document.documentType {
                                        Text(store.documentTypes[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable.documentTypeNotAssignedPicker)
                                    }
                                }
                                .foregroundColor(.gray)
                                .navigationTitle(Text(.localizable.documentType))
                            }
                        }

                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: StoragePathManager.self,
                                document: $document,
                                store: store
                            )
                        }) {
                            HStack {
                                Text(.localizable.storagePath)
                                Spacer()
                                Group {
                                    if let id = document.storagePath {
                                        Text(store.storagePaths[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable.storagePathNotAssignedPicker)
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }

                        NavigationLink(destination: {
                            DocumentTagEditView(document: $document)
                                .navigationTitle(Text(.localizable.tags))
                        }) {
                            if document.tags.isEmpty {
                                Text(.localizable.createDocumentNoTags)
                            } else {
                                TagsView(tags: document.tags.compactMap { store.tags[$0] })
                                    .contentShape(Rectangle())
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
                .errorOverlay(errorController: errorController)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    title()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    switch status {
                    case .none:
                        Button(String(localized: .localizable.save)) {
                            Task {
                                withAnimation {
                                    status = .uploading
                                }

                                await upload()
                            }
                        }
                        .transition(.opacity)

                    case .uploading:
                        ProgressView()
                            .transition(.opacity)

                    case .complete:
                        Label(String(localized: .localizable.documentUploadComplete), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .labelStyle(.iconOnly)
                    case .error:
                        Label(String(localized: .localizable.documentUploadError), systemImage: "exclamationmark.triangle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .task {
                do {
                    try await store.fetchAll()
                } catch {
                    errorController.push(error: error)
                }
            }
        }

        .errorOverlay(errorController: errorController)
    }
}
