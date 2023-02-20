//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import SwiftUI

#if os(macOS)
import Cocoa
typealias UIImage = NSImage
#endif

extension Text {
//    func correspondentText() -> some View {
//        self.font(.title).bold()
//    }

    static func titleCorrespondent(value: Correspondent?) -> Text {
        if let correspondent = value {
            return Text("\(correspondent.name): ").bold().foregroundColor(.blue)
        }
        else {
            return Text("")
        }
    }

    static func titleDocumentType(value: DocumentType?) -> Text {
        if let documentType = value {
            return Text("\(documentType.name)").bold().foregroundColor(.orange)
        }
        else {
            return Text("")
        }
    }
}

struct DocumentCell: View {
    @EnvironmentObject var store: DocumentStore

    let document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?

    var body: some View {
        HStack(alignment: .top) {
            AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 150, height: 150, alignment: .top)
                    .cornerRadius(5)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
            } placeholder: {
                Rectangle().fill(.gray).scaledToFit().overlay(ProgressView())
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading) {
                Group {
                    Text.titleCorrespondent(value: correspondent)
                        + Text("\(document.title)")
                }.task {
                    if let cId = document.correspondent {
                        correspondent = await store.getCorrespondent(id: cId)
                    }

                    if let dId = document.documentType {
                        documentType = await store.getDocumentType(id: dId)
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)
            }
        }
    }
}

struct DocumentDetailView: View {
    @EnvironmentObject var store: DocumentStore

    @State private var editing = false
    @Binding var document: Document

    @State private var correspondent: Correspondent?
    @State private var documentType: DocumentType?

    @State private var previewUrl: URL?
    @State private var previewLoading = false

    func loadData() async {
        correspondent = nil
        documentType = nil
        if let cId = document.correspondent {
            correspondent = await store.getCorrespondent(id: cId)
        }
        if let dId = document.documentType {
            documentType = await store.getDocumentType(id: dId)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    (
                        Text.titleCorrespondent(value: correspondent)
                            + Text("\(document.title)")
                    ).font(.title)
                }.task {
                    await loadData()
                }
                .onChange(of: document) { _ in
                    Task {
                        await loadData()
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .font(.headline)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)

                GeometryReader { geometry in
                    Button(action: {
                        Task {
                            if previewLoading {
                                return
                            }
                            previewLoading = true
                            previewUrl = await getPreviewImage(documentID: document.id)
                            previewLoading = false
                        }
                    }) {
                        AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                            image in
                            ZStack {
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: geometry.size.width, alignment: .top)
                                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                                    .opacity(previewLoading ? 0.6 : 1.0)

                                if previewLoading {
                                    ProgressView()
                                }
                            }.animation(.default, value: previewLoading)

                        } placeholder: {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .quickLookPreview($previewUrl)
                }

            }.padding()
        }
        .toolbar {
            Button("Edit") {
                editing.toggle()
            }.sheet(isPresented: $editing) {
                DocumentEditView(document: $document)
            }
        }
//        .navigationTitle(
//            Text.titleCorrespondent(value: correspondent)
//                + Text("\(document.title)")
//        )
        .refreshable {
//            Task {
            if let document = await store.getDocument(id: document.id) {
                self.document = document
            }
//            }
        }
    }
}

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var store: DocumentStore

    @Binding var documentBinding: Document

    @State var document: Document
    @State var modified: Bool = false

    @State var correspondentID: UInt = 0
    @State var documentTypeID: UInt = 0

    init(document: Binding<Document>) {
        self._documentBinding = document
        self._document = State(initialValue: document.wrappedValue)

        if let c = document.correspondent.wrappedValue {
            self._correspondentID = State(initialValue: c)
        }

        if let d = document.documentType.wrappedValue {
            self._documentTypeID = State(initialValue: d)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $document.title) {}
                    DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                }
                Section {
                    Picker("Correspondent", selection: $correspondentID) {
                        Text("None").tag(UInt(0))
                        ForEach(store.correspondents.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(c.id)
                        }
                    }
                    Picker("Document type", selection: $documentTypeID) {
                        Text("None").tag(UInt(0))
                        ForEach(store.documentTypes.sorted { $0.value.name < $1.value.name }, id: \.value.id) { _, c in
                            Text("\(c.name)").tag(c.id)
                        }
                    }
                }
            }.toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        documentBinding = document
                        // @TODO: Kick off API call to save the document
                        dismiss()
                    }
                    .bold()
                    .disabled(!modified)
                }

            }.onChange(of: document) { _ in
                modified = true
            }.onChange(of: correspondentID) { value in
                document.correspondent = value > 0 ? value : nil
            }.onChange(of: documentTypeID) { value in
                document.documentType = value > 0 ? value : nil
            }
            .task {
                async let _ = await store.fetchAllCorrespondents()
                async let _ = await store.fetchAllDocumentTypes()
            }
        }
    }
}

struct FilterView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Text("Filter")
                .navigationTitle("Filter")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Clear", role: .cancel) {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }.bold()
                    }
                }
        }
    }
}

class DebounceObject: ObservableObject {
    @Published var text: String = ""
    @Published var debouncedText: String = ""
    private var tasks = Set<AnyCancellable>()

    init(delay: TimeInterval = 0.5) {
        $text
            .removeDuplicates()
            .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
            .sink(receiveValue: { [weak self] value in
                self?.debouncedText = value
            })
            .store(in: &tasks)
    }
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()

//    @State private var navPath = NavigationPath()

    @State var lastSearchString: String?
    @StateObject var searchDebounce = DebounceObject()

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    func loadInitial() async {
        store.isLoading = true
        // @TODO: Make HTTP requests concurrently
        async let _ = await store.fetchAllCorrespondents()
        async let _ = await store.fetchAllDocumentTypes()
        await store.fetchDocuments(searchText: searchDebounce.debouncedText == "" ? nil : searchDebounce.debouncedText, clear: true)
        store.isLoading = false
    }

    func loadNextPage() async {
        await store.fetchDocuments(searchText: searchDebounce.debouncedText == "" ? nil : searchDebounce.debouncedText, clear: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach($store.documents, id: \.id) { $document in
                        NavigationLink(destination: {
                            DocumentDetailView(document: $document)
                                .navigationBarTitleDisplayMode(.inline)
                        }, label: {
                            DocumentCell(document: document).task {
                                if document == store.documents.last {
                                    await loadNextPage()
                                }
                            }
                        })
                        .buttonStyle(.plain)
                        .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
//                        .listRowBackground(Color.clear)
//                        .listRowSeparatorTint(.clear)
//                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    }
                }.opacity(store.isLoading ? 0.5 : 1.0)
            }
            .animation(.default, value: store.documents)
//                if store.isLoading && store.currentPage == 1 {
//                    ProgressView()
//                }
            .toolbar {
//                ToolbarItem(placement: .principal) {
//                    Text("Hi")
//                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showFilterModal.toggle() }) {
                        Label("Filter", systemImage:
                            //                            "line.3.horizontal.decrease.circle.fill" :
                            "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilterModal) { FilterView() }
            .task {
                if store.currentPage == 1 && store.documents.isEmpty {
                    await loadInitial()
                }
            }
            .refreshable {
                Task {
                    await loadInitial()
                }
            }
            .navigationTitle("Documents")
//            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchDebounce.text, placement: .automatic, suggestions: {
                ForEach(searchSuggestions, id: \.self) { v in
                    Text(v).searchCompletion(v)
                }
            })
            .onChange(of: searchDebounce.text) { value in
                if value == "" {
                    searchSuggestions = []

                    if let last = lastSearchString {
                        if last.lowercased() != searchDebounce.debouncedText.lowercased() {
                            searchDebounce.debouncedText = ""
                        }
                    }
                }
            }
            .onChange(of: searchDebounce.debouncedText) { _ in
                if searchDebounce.debouncedText == "" {
                    searchSuggestions = []
                }
                else {
                    Task {
                        searchSuggestions = await getSearchCompletion(term: searchDebounce.debouncedText)
                    }
                }
                if let last = lastSearchString {
                    if last.lowercased() == searchDebounce.debouncedText.lowercased() {
                        // skip search as it's the same as before
                        return
                    }
                }

                Task {
                    store.isLoading = true
                    await loadInitial()
                    lastSearchString = searchDebounce.debouncedText
                    store.isLoading = false
                }
            }
        }
        .environmentObject(store)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
