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

let API_TOKEN = "***REMOVED***"
let API_BASE_URL = "https://***REMOVED***/api/"

struct DocumentResponse: Codable {
    var count: UInt
    var next: String?
    var previous: String?
    var results: [Document]
}

struct Document: Codable, Identifiable, Equatable, Hashable {
    var id: UInt
    var added: String
    var title: String
    var documentType = "Document"
    var correspondent = "Person"

    var created: Date

    private enum CodingKeys: String, CodingKey {
        case id, added, title, created
    }
}

func getDocuments(page: UInt) async -> DocumentResponse? {
    let urlStr = API_BASE_URL + "documents/?page=\(page)"
    print(urlStr)
    guard let url = URL(string: urlStr) else {
        fatalError("Invalid URL")
    }

//    print("Go getDocuments")

    var request = URLRequest(url: url)
    request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

    do {
        let (data, _) = try await URLSession.shared.data(for: request)

//        print(String(decoding: data, as: UTF8.self))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DocumentResponse.self, from: data)
//        print(decoded)

        return decoded
    }
    catch {
        print("Invalid data")
        return nil
    }
}

@MainActor
class DocumentStore: ObservableObject {
    @Published var documents: [Document] = []
    @Published private(set) var isLoading = false

    private var hasNextPage = true
    private(set) var currentPage: UInt = 1

    func fetchDocuments() async {
        if !hasNextPage { return }

        isLoading = true
        guard let response = await getDocuments(page: currentPage) else {
            return
        }

        documents += response.results

        if response.next != nil {
            currentPage += 1
        }
        else {
            hasNextPage = false
        }

        isLoading = false
    }
}

struct AuthAsyncImage<Content: View, Placeholder: View>: View {
    @State var uiImage: UIImage?

    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        url: URL?, @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    func getImage() async -> UIImage? {
        guard let url = url else { return nil }

//        print("Load image at \(url)")

        var request = URLRequest(url: url)
        request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: request)
            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                fatalError("Did not get good response for image")
            }

//            try await Task.sleep(for: .seconds(2))

            return UIImage(data: data)
        }
        catch { return nil }
    }

    var body: some View {
        if let uiImage = uiImage {
#if os(macOS)
            content(Image(nsImage: uiImage))
#else
            content(Image(uiImage: uiImage))
#endif
        }
        else {
            placeholder().task {
                let image = await getImage()
                withAnimation {
                    self.uiImage = image
                }
            }
        }
    }
}

struct DocumentCell: View {
    let document: Document

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
                    Text("\(document.correspondent): ").bold()
                        + Text("\(document.title) ")
                }
                Text("\(document.documentType) ")
                    .font(.subheadline)
                    .foregroundColor(Color.orange)
                    .bold()

                Text(document.created, style: .date)
            }
        }
    }
}

struct DocumentDetailView: View {
    @State private var editing = false
    @Binding var document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    Text("\(document.correspondent): ").font(.title).bold()
                        + Text("\(document.title) ").font(.title)
                }
                Text("\(document.documentType) ")
                    .font(.headline)
                    .foregroundColor(.orange)
                    .bold()

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
                await store.fetchDocuments()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
