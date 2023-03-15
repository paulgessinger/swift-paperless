//
//  CreateDocumentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI
import UniformTypeIdentifiers

extension NSMutableData {
    func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

struct CreateDocumentView: View {
    enum Status {
        case none
        case uploading
        case complete
        case error
    }

    @ObservedObject var attachmentManager: AttachmentManager
    @EnvironmentObject private var store: DocumentStore

    @State private var document = ProtoDocument()
    @State private var selectedState = FilterState()
    @State private var status = Status.none

    @State private var error: String = ""
    @State private var showingError = false

    var callback: (() -> Void)?

    func setError(_ value: String) {
        error = value
        showingError = true
    }

    func upload() async {
        guard let url = attachmentManager.documentUrl else {
            return
        }

        var request = URLRequest.common(url: Endpoint.createDocument().url!)

        let mp = MultiPartFormDataRequest()
        mp.add(name: "title", string: document.title)

        if let corr = document.correspondent {
            mp.add(name: "correspondent", string: String(corr))
        }

        if let dt = document.documentType {
            mp.add(name: "document_type", string: String(dt))
        }

        for tag in document.tags {
            mp.add(name: "tags", string: String(tag))
        }

        do {
            try mp.add(name: "document", url: url)
        }
        catch {
            setError("Unable to make request:\n\(error)")
        }
        mp.addTo(request: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let hres = response as? HTTPURLResponse, hres.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? "No body"

                setError("StatusCode \(hres.statusCode)\n\(body)")
            }
        }
        catch {
            print("Error uploading: \(error)")
            setError(String(describing: error))
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

        callback?()
    }

    var body: some View {
        //        Text(attachmentManager.text.joined(separator: "\n"))
//            Divider()
        NavigationStack {
            VStack {
                if attachmentManager.isLoading {
                    ProgressView()
                }
                else {
                    if let error = attachmentManager.error {
                        Text(String(describing: error))
                    }
                    else {
                        HStack {
                            Group {
                                if let preview = attachmentManager.previewImage {
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
                    }
                }
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
                                }.map { ($0.value.id, $0.value.name) },
                                filterMode: false
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
                                }.map { ($0.value.id, $0.value.name) },
                                filterMode: false
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
                            TagSelectionView(tags: store.tags,
                                             selectedTags: $selectedState.tags,
                                             filterMode: false)
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
                .onChange(of: attachmentManager.documentUrl) { url in
                    if let url = url, document.title.isEmpty {
                        document.title = url.lastPathComponent
                    }
                }

                .onChange(of: selectedState.correspondent) { value in
                    switch value {
                    case .only(let id):
                        document.correspondent = id
                    case .notAssigned:
                        document.correspondent = nil
                    case .any:
                        break
                    }
                }

                .onChange(of: selectedState.documentType) { value in
                    switch value {
                    case .only(let id):
                        document.documentType = id
                    case .notAssigned:
                        document.documentType = nil
                    case .any:
                        break
                    }
                }

                .onChange(of: selectedState.tags) { value in
                    switch value {
                    case .only(let ids):
                        document.tags = ids
                    case .notAssigned:
                        document.tags = []
                    case .any:
                        break
                    }
                }

                .alert("\(error)", isPresented: $showingError) {
                    Button("Ok", role: .cancel) {}
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "leaf.fill")
                            .foregroundColor(.accentColor)
                        Text("Paperless")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    switch status {
                    case .none:
                        if !attachmentManager.isLoading {
                            Button("Save") {
                                Task {
                                    withAnimation {
                                        status = .uploading
                                    }

                                    await upload()
                                }
                            }
                            .transition(.opacity)
                        }

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
                await store.fetchAll()
            }
        }
    }
}
