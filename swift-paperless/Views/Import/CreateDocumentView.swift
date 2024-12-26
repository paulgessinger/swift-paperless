//
//  CreateDocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import DataModel
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

private struct DetailView: View {
    private struct CopyButton: View {
        var logs: URL

        @EnvironmentObject private var errorController: ErrorController

        @State private var copied = false

        var body: some View {
            Button {
                do {
                    let data = try Data(contentsOf: logs)
                    let string = String(data: data, encoding: .utf8)
                    UIPasteboard.general.string = string
                    Haptics.shared.notification(.success)
                    copied = true
                } catch {
                    Logger.shared.error("Unable to load logs from file: \(error)")
                    errorController.push(error: error)
                }
            } label: {
                if !copied {
                    Label(localized: .localizable(.copyToClipboard),
                          systemImage: "doc.on.doc")
                } else {
                    Label(localized: .localizable(.copiedToClipboard),
                          systemImage: "doc.on.doc.fill")
                }
            }
        }
    }

    var body: some View {
        Form {
            LogRecordExportButton { state, export in
                switch state {
                case .none:
                    Button {
                        export()
                    } label: {
                        Label(String(localized: .localizable(.logsExport)), systemImage: "text.word.spacing")
                            .accentColor(.primary)
                    }

                case .loading:
                    LogRecordExportButton.loadingView()

                case let .loaded(logs):
                    CopyButton(logs: logs)

                case let .error(error):
                    Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
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

    init(sourceUrl url: URL,
         callback: @escaping () -> Void = {},
         share: Bool = false,
         title: String? = nil)
    {
        sourceUrl = url
        _document = State(initialValue: ProtoDocument(title: url.deletingPathExtension().lastPathComponent))
        self.callback = callback
        self.share = share
        self.title = title ?? String(localized: .localizable(.documentAdd))
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
                        Text(.localizable(.pages(thumbnailView.pageCount)))
                            .font(.subheadline)
                    }
                    Spacer()
                }
                .padding()
                Spacer()

                Form {
                    if share, connectionManager.storedConnection != nil {
                        Section(String(localized: .settings(.activeServer))) {
                            ConnectionSelectionMenu(connectionManager: connectionManager,
                                                    animated: false)
                        }
                    }

                    Section {
                        TextField(String(localized: .localizable(.documentEditTitleLabel)), text: $document.title) {}
                            .clearable($document.title)

                        DocumentAsnEditingView(document: $document, isValid: $isAsnValid)
                            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

                        DatePicker(String(localized: .localizable(.documentEditCreatedDateLabel)), selection: $document.created, displayedComponents: .date)
                    }

                    Section {
                        NavigationLink(destination: {
                            CommonPickerEdit(
                                manager: CorrespondentManager.self,
                                document: $document,
                                store: store
                            )
                            .navigationTitle(String(localized: .localizable(.correspondent)))
                        }) {
                            HStack {
                                Text(.localizable(.correspondent))
                                Spacer()
                                Group {
                                    if let id = document.correspondent {
                                        Text(store.correspondents[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable(.correspondentNotAssignedPicker))
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
                            .navigationTitle(Text(.localizable(.documentType)))
                        }) {
                            HStack {
                                Text(.localizable(.documentType))
                                Spacer()
                                Group {
                                    if let id = document.documentType {
                                        Text(store.documentTypes[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable(.documentTypeNotAssignedPicker))
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
                                Text(.localizable(.storagePath))
                                Spacer()
                                Group {
                                    if let id = document.storagePath {
                                        Text(store.storagePaths[id]?.name ?? "ERROR")
                                    } else {
                                        Text(.localizable(.storagePathNotAssignedPicker))
                                    }
                                }
                                .foregroundColor(.gray)
                            }
                        }

                        NavigationLink(destination: {
                            DocumentTagEditView(document: $document)
                                .navigationTitle(Text(.localizable(.tags)))
                        }) {
                            if document.tags.isEmpty {
                                Text(.localizable(.createDocumentNoTags))
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
                ToolbarItem(placement: .topBarTrailing) {
                    switch status {
                    case .none:
                        Button(String(localized: .localizable(.save))) {
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
                        Label(String(localized: .localizable(.documentUploadComplete)), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .labelStyle(.iconOnly)

                    case .error:
                        Label(String(localized: .localizable(.documentUploadError)), systemImage: "exclamationmark.triangle")
                            .labelStyle(.iconOnly)
                    }
                }

                if share {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink {
                            DetailView()
                        } label: {
                            Label(localized: .localizable(.details),
                                  systemImage: "info.circle")
                        }
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

// - MARK: Previews

private struct PreviewHelperView: View {
    @StateObject private var store = DocumentStore(repository: PreviewRepository())
    @StateObject private var errorController = ErrorController()
    @StateObject private var connectionManager = ConnectionManager(previewMode: true)

    private let url = Bundle.main.url(forResource: "demo2", withExtension: "pdf")!

    let share: Bool

    var body: some View {
        CreateDocumentView(sourceUrl: url, share: share)
            .environmentObject(store)
            .environmentObject(errorController)
            .environmentObject(connectionManager)
    }
}

#Preview("Import") {
    PreviewHelperView(share: false)
}

#Preview("Share") {
    PreviewHelperView(share: true)
}
