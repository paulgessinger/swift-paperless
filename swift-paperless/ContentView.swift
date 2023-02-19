//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
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
            return Text("\(documentType.name): ").bold().foregroundColor(.orange)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    (
                        Text.titleCorrespondent(value: correspondent)
                            + Text("\(document.title)")
                    ).font(.title)
                }.task {
                    if let cId = document.correspondent {
                        correspondent = await store.getCorrespondent(id: cId)
                    }

                    if let dId = document.documentType {
                        documentType = await store.getDocumentType(id: dId)
                    }
                }

                Text.titleDocumentType(value: documentType)
                    .font(.headline)
                    .foregroundColor(Color.orange)

                Text(document.created, style: .date)

                GeometryReader { geometry in
                    AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                        image in
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: geometry.size.width, alignment: .top)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                    } placeholder: {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

            }.padding()
        }.toolbar {
            Button("Edit") {
                editing.toggle()
            }.sheet(isPresented: $editing) {
                DocumentEditView(document: $document)
            }
        }
    }
}

struct DocumentEditView: View {
    @Environment(\.dismiss) var dismiss

    @Binding var documentBinding: Document

    @State var document: Document
    @State var modified: Bool = false

    init(document: Binding<Document>) {
        self._documentBinding = document
        self._document = State(initialValue: document.wrappedValue)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Title", text: $document.title) {}
                    DatePicker("Created date", selection: $document.created, displayedComponents: .date)
                }
            }.toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        documentBinding = document
                        // @TODO: Kick off API call to save the document
                        dismiss()
                    }.disabled(!modified)
                }
            }.onChange(of: document) { _ in
                modified = true
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()

//    @State private var navPath = NavigationPath()

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
                                    await store.fetchDocuments()
                                }
                            }
                        })
                        .buttonStyle(.plain)
                    }.padding()
                }
                .animation(.default, value: store.documents)

                if store.isLoading && store.currentPage == 1 {
                    ProgressView()
                }
            }
//            .navigationDestination(for: Document.self) { document in
//                DocumentDetailView(document: document)
//                    .navigationBarTitleDisplayMode(.inline)
//            }
            .navigationTitle("Documents")
            .task {
                // @TODO: Make HTTP requests concurrently
                async let _ = await store.fetchAllCorrespondents()
                async let _ = await store.fetchAllDocumentTypes()
                await store.fetchDocuments()
            }
        }.environmentObject(store)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
