//
//  DocumentMetadataView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

import DataModel
import os
import SwiftUI

private struct Row<Label: View, Value: View>: View {
    let label: () -> Label
    let value: () -> Value

    var body: some View {
        HStack {
            label()
                .foregroundStyle(.secondary)
            Spacer()
            value()
        }
    }
}

extension Row where Label == Text {
    init(_ label: LocalizedStringKey, value: @escaping () -> Value) {
        self.init(label: { Text(label) }, value: value)
    }
}

extension Row where Value == Text {
    init(label: @escaping () -> Label, value: String) {
        self.init(label: label, value: { Text(value) })
    }
}

extension Row where Label == Text, Value == Text {
    init(_ label: LocalizedStringKey, value: String) {
        self.init(label: { Text(label) }, value: { Text(value) })
    }
}

private struct WideRow<Label: View, Value: View>: View {
    let label: () -> Label
    let value: () -> Value

    var body: some View {
        VStack(alignment: .leading) {
            label()
                .foregroundStyle(.secondary)
            value()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WideRow where Label == Text {
    init(_ label: LocalizedStringKey, value: @escaping () -> Value) {
        self.init(label: { Text(label) }, value: value)
    }
}

extension WideRow where Value == Text {
    init(label: @escaping () -> Label, value: String) {
        self.init(label: label, value: { Text(value) })
    }
}

extension WideRow where Label == Text, Value == Text {
    init(_ label: LocalizedStringKey, value: String) {
        self.init(label: { Text(label) }, value: { Text(value) })
    }
}

private struct Section<Title: View, Content: View>: View {
    @ViewBuilder
    let title: () -> Title

    @ViewBuilder
    let content: () -> Content

    @ScaledMetric(relativeTo: .body) private var spacing = 5.0

    init(@ViewBuilder title: @escaping () -> Title,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(spacing: spacing) {
            title()
                .font(.headline)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .bottomLeading)
                .padding(.horizontal)
            VStack {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.tertiary)
            )
        }
        .padding()
    }
}

extension Section where Title == EmptyView {
    init(@ViewBuilder content: @escaping () -> Content) {
        title = { EmptyView() }
        self.content = content
    }
}

extension Section where Title == Text {
    init(_ title: LocalizedStringKey,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.init(title: { Text(title) }, content: content)
    }

    init(_ title: String,
         @ViewBuilder content: @escaping () -> Content)
    {
        self.init(title: { Text(title) }, content: content)
    }
}

struct DocumentMetadataView: View {
    @Binding var document: Document
    @Binding var metadata: Metadata?

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    private var loaded: Bool {
        metadata != nil
    }

    private var metadataSection: some View {
        ScrollView(.vertical) {
            Section {
                Row(.documentMetadata(.modifiedDate)) {
                    if let modified = document.modified {
                        Text(modified, style: .date)
                    } else {
                        Text(.localizable(.none))
                    }
                }
                Divider()
                Row(.documentMetadata(.addedDate)) {
                    if let added = document.added {
                        Text(added, style: .date)
                    } else {
                        Text(.localizable(.none))
                    }
                }

                VStack {
                    if let metadata {
                        Divider()
                        WideRow(.documentMetadata(.mediaFilename)) {
                            Text(metadata.mediaFilename)
                                .textSelection(.enabled)
                        }

                        Divider()
                        WideRow(.documentMetadata(.originalFilename)) {
                            Text(metadata.originalFilename)
                                .textSelection(.enabled)
                        }

                        Divider()
                        WideRow(.documentMetadata(.originalChecksum)) {
                            Text(metadata.originalChecksum)
                                .italic()
                                .textSelection(.enabled)
                        }

                        Divider()
                        Row(.documentMetadata(.originalFilesize)) {
                            Text(metadata.originalSize.formatted(.byteCount(style: .file)))
                        }

                        Divider()
                        Row(.documentMetadata(.originalMimeType)) {
                            Text(metadata.originalMimeType)
                                .textSelection(.enabled)
                        }

                        if let archiveChecksum = metadata.archiveChecksum {
                            Divider()
                            WideRow(.documentMetadata(.archiveChecksum)) {
                                Text(archiveChecksum)
                                    .italic()
                                    .textSelection(.enabled)
                            }
                        }

                        if let archiveSize = metadata.archiveSize {
                            Divider()
                            Row(.documentMetadata(.archiveFilesize)) {
                                Text(archiveSize.formatted(.byteCount(style: .file)))
                            }
                        }
                    } else {
                        ProgressView()
                            .padding()
                    }
                }
                .animation(.spring.delay(0.2), value: loaded)
            }
            .animation(.spring, value: loaded)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    var body: some View {
        NavigationStack {
            metadataSection

                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle(.documentMetadata(.metadata))

                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        CancelIconButton()
                    }
                }
        }

        .errorOverlay(errorController: errorController, offset: 20)
    }
}

// - MARK: Preview

private struct PreviewHelper: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository(downloadDelay: 3.0))
    @StateObject var errorController = ErrorController()

    @State var document: Document?
    @State var metadata: Metadata?

    var body: some View {
        NavigationStack {
            VStack {
                if document != nil {
                    DocumentMetadataView(document: Binding($document)!, metadata: $metadata)
                }
            }
            .task {
                document = try? await store.document(id: 1)
                if let document {
                    metadata = try? await store.repository.metadata(documentId: document.id)
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

#Preview {
    PreviewHelper()
}
