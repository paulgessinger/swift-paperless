//
//  CreateDocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

struct CreateDocumentView: View {
    private enum Status {
        case none
        case uploading
        case complete
        case error
    }

    let sourceUrl: URL

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var document = ProtoDocument()
    @State private var status = Status.none

    let callback: () -> Void
    let share: Bool
    let title: String

    init(sourceUrl url: URL, callback: @escaping () -> Void = {}, share: Bool = false, title: String = String(localized: .localizable.documentAdd)) {
        sourceUrl = url
        _document = State(initialValue: ProtoDocument(title: url.lastPathComponent))
        self.callback = callback
        self.share = share
        self.title = title
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

    private func resetDocument() {
        document.asn = nil
        document.documentType = nil
        document.correspondent = nil
        document.tags = []
        document.storagePath = nil
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
                    if share, let stored = connectionManager.storedConnection {
                        HStack {
                            Text(.settings.activeServer)
                            Menu {
                                ConnectionSelectionMenu(connectionManager: connectionManager)
                            } label: {
                                Text(stored.url.absoluteString)
                                    .font(.body)
                                    .foregroundStyle(.gray)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                Label(String(localized: .settings.chooseServerAccessibilityLabel),
                                      systemImage: "chevron.up.chevron.down")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }

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
                            .navigationTitle(Text(.localizable.documentType))
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
            }

            .navigationBarTitleDisplayMode(.inline)

            .navigationTitle(title)

            .toolbar {
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

            .onReceive(store.documentEventPublisher) { event in
                switch event {
                case .repositoryWillChange:
                    resetDocument()
                default: break
                }
            }
        }

        .errorOverlay(errorController: errorController, offset: 20)
    }
}
