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
    @State private var selectedState = FilterState()
    @State private var status = Status.none

    @State private var previewImage: Image?

    var callback: () -> Void

    init(sourceUrl url: URL, callback: @escaping () -> Void = {}, @ViewBuilder title: @escaping () -> Title = { LogoView() }) {
        sourceUrl = url
        _document = State(initialValue: ProtoDocument(title: url.lastPathComponent))
        _selectedState = State(initialValue: FilterState(correspondent: .notAssigned, documentType: .notAssigned))
        self.title = title
        self.callback = callback
    }

    func upload() async {
        do {
            try await store.repository.createDocument(document, file: sourceUrl)
        }
        catch {
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
        }
        catch {}

        callback()
    }

    var body: some View {
        //        Text(attachmentManager.text.joined(separator: "\n"))
//            Divider()
        NavigationStack {
            VStack {
                HStack {
                    Group {
                        if let preview = previewImage {
                            preview
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100, alignment: .top)
                                .cornerRadius(10)
                        }
                        else {
                            Rectangle()
                                .fill(Color.systemGroupedBackground)
                                .frame(width: 100, height: 100)
                                .cornerRadius(10)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray, lineWidth: 1))

                    Text(document.title)
                    Spacer()
                }
                .padding()
                Spacer()

                Form {
                    Section {
                        TextField("Title", text: $document.title) {}
                        DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                    }
                    Section {
                        NavigationLink(destination: {
                            CommonPicker(
                                selection: $selectedState.correspondent,
                                elements: store.correspondents.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }) {
                            HStack {
                                Text("Correspondent")
                                Spacer()
                                Group { () -> Text in
                                    var label = "None"
                                    switch selectedState.correspondent {
                                    case .any:
                                        print("Selected 'any' correspondent, this should not happen")
                                    case .notAssigned:
                                        break
                                    case .only(let id):
                                        label = store.correspondents[id]?.name ?? "None"
                                    }
                                    return Text(label)
                                        .foregroundColor(.gray)
                                }
                            }
                        }

                        NavigationLink(destination: {
                            CommonPicker(
                                selection: $selectedState.documentType,
                                elements: store.documentTypes.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }) {
                            HStack {
                                Text("Document type")
                                Spacer()
                                Group { () -> Text in
                                    var label = "None"
                                    switch selectedState.documentType {
                                    case .any:
                                        print("Selected 'any' document type, this should not happen")
                                    case .notAssigned:
                                        break
                                    case .only(let id):
                                        label = store.documentTypes[id]?.name ?? "None"
                                    }
                                    return Text(label)
                                        .foregroundColor(.gray)
                                }
                            }
                        }

                        NavigationLink(destination: {
                            TagEditView(document: $document)
                                .navigationTitle("Tags")
                        }) {
                            if document.tags.isEmpty {
                                Text("No tags")
                            }
                            else {
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
//                    switch title {
//                    case .logo:
//                        LogoView()
//                    case .text(let value):
//                        Text(value)
//                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    switch status {
                    case .none:
                        Button("Save") {
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
                        Label("Upload complete", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .labelStyle(.iconOnly)
                    case .error:
                        Label("Upload error", systemImage: "exclamationmark.triangle")
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .task {
                previewImage = pdfPreview(url: sourceUrl)
                await store.fetchAll()
            }
        }
    }
}
