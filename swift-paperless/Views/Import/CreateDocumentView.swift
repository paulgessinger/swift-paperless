//
//  CreateDocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import os
import SwiftUI
import UniformTypeIdentifiers

private struct ThumbnailView: View {
    let sourceUrl: URL

    private var pdfView: PDFThumbnail? = nil

    init(sourceUrl: URL) {
        self.sourceUrl = sourceUrl
        if sourceUrl.pathExtension == "pdf" {
            pdfView = PDFThumbnail(file: sourceUrl)
        }
    }

    var pageCount: Int {
        pdfView?.document.pageCount ?? 1
    }

    var body: some View {
        if let pdfView {
            pdfView
        } else {
            if let data = try? Data(contentsOf: sourceUrl), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(1.0, contentMode: .fill)
            } else {
                Text("ERROR")
            }
        }
    }
}

struct CreateDocumentView: View {
    private enum Status {
        case none
        case uploading
        case complete
        case error
    }

    let sourceUrl: URL
    let callback: () -> Void
    let share: Bool
    let title: String

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var document = ProtoDocument()
    @State private var status = Status.none
    @State var isAsnValid = true

    private var isDocumentValid: Bool {
        isAsnValid && !document.title.isEmpty
    }

    private var thumbnailView: ThumbnailView

    init(sourceUrl url: URL, callback: @escaping () -> Void = {}, share: Bool = false, title: String = String(localized: .localizable.documentAdd)) {
        sourceUrl = url
        _document = State(initialValue: ProtoDocument(title: url.deletingPathExtension().lastPathComponent))
        self.callback = callback
        self.share = share
        self.title = title
        thumbnailView = ThumbnailView(sourceUrl: sourceUrl)
    }

    func upload() async {
        do {
            try await store.create(document: document, file: sourceUrl)
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
                        thumbnailView
                            .background(.white)
                            .frame(width: 100, height: 100, alignment: .top)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.gray, lineWidth: 1))

                    VStack(alignment: .leading) {
                        Text(document.title)
                            .font(.headline)
                        Text(.localizable.pages(thumbnailView.pageCount))
                            .font(.subheadline)
                    }
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

                        DocumentAsnEditingView(document: $document, isValid: $isAsnValid)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

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
                        .disabled(!isDocumentValid)

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

            .onReceive(store.eventPublisher) { event in
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
