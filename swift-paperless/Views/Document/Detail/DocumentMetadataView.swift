//
//  DocumentMetadataView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.2024.
//

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
        Divider()
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
        Divider()
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
                .font(.title3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            VStack {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()

            .background(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
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
    let document: Document
    @Binding var metadata: Metadata?

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @Environment(\.dismiss) private var dismiss

    private var loaded: Bool {
        metadata != nil
    }

    var body: some View {
        ScrollView(.vertical) {
            Section(.localizable(.documentMetadata)) {
                if let modified = document.modified {
                    Row(.localizable(.documentModifiedDate)) {
                        Text(modified, style: .date)
                    }
                }
                if let added = document.added {
                    Row(.localizable(.documentAddedDate)) {
                        Text(added, style: .date)
                    }
                }

                VStack {
                    if let metadata {
                        WideRow(.localizable(.documentMediaFilename),
                                value: metadata.mediaFilename)

                        WideRow(.localizable(.documentOriginalFilename),
                                value: metadata.originalFilename)

                        WideRow(.localizable(.documentOriginalChecksum)) {
                            Text(metadata.originalChecksum)
                                .italic()
                        }

                        Row(.localizable(.documentOriginalFilesize)) {
                            Text(metadata.originalSize.formatted(.byteCount(style: .file)))
                        }

                        Row(.localizable(.documentOriginalMimeType),
                            value: metadata.originalMimeType)

                        if let archiveChecksum = metadata.archiveChecksum {
                            WideRow(.localizable(.documentArchiveChecksum)) {
                                Text(archiveChecksum)
                                    .italic()
                            }
                        }

                        if let archiveSize = metadata.archiveSize {
                            Row(.localizable(.documentArchiveFilesize)) {
                                Text(archiveSize.formatted(.byteCount(style: .file)))
                            }
                        }
                    }
                }
                .animation(.spring.delay(0.2), value: loaded)
            }

            .padding(.top, 30)
        }

        .animation(.spring, value: loaded)

        .overlay(alignment: .topLeading) {
            HStack {
                Spacer()
                Label(localized: .localizable(.back), systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.largeTitle)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .thickMaterial)
                    .padding([.top, .horizontal])
                    .onTapGesture {
                        dismiss()
                    }
            }
        }
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
                if let document {
                    DocumentMetadataView(document: document, metadata: $metadata)
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
