//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

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
    @Published private(set) var documents: [Document] = []
    @Published private(set) var isLoading = false

    private var hasNextPage = true
    private(set) var currentPage: UInt = 1

    func fetch() async {
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

        print("Load image at \(url)")

        var request = URLRequest(url: url)
        request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: request)
            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                fatalError("Did not get good response for image")
            }

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
                self.uiImage = await getImage()
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
                    .foregroundColor(.accentColor)
                    .bold()

                Text(document.created, style: .date)
            }
        }
    }
}

struct DocumentDetailView: View {
    let document: Document

    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                Group {
                    Text("\(document.correspondent): ").font(.title).bold()
                        + Text("\(document.title) ").font(.title)
                }
                Text("\(document.documentType) ")
                    .font(.headline)
                    .foregroundColor(.accentColor)
                    .bold()

                Text(document.created, style: .date)

                GeometryReader { geometry in
                    HStack {
//                        Spacer()
                        AuthAsyncImage(url: URL(string: "\(API_BASE_URL)documents/\(document.id)/thumb/")) {
                            image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: geometry.size.width, alignment: .top)
                                //                            .cornerRadius(5)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                        } placeholder: {
                            Rectangle().fill(.gray).scaledToFit().overlay(ProgressView())
                        }
                        .frame(width: geometry.size.width)
//                        Spacer()
                    }
                }

            }.padding()
        }
    }
}

struct ContentView: View {
    @StateObject private var store = DocumentStore()

    @State private var navPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navPath) {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach(store.documents, id: \.id) { document in
                        NavigationLink(value: document) {
                            DocumentCell(document: document).task {
                                if document == store.documents.last {
                                    await store.fetch()
                                }
                            }
                        }.buttonStyle(.plain)
                    }.padding()
                }

                if store.isLoading && store.currentPage == 1 {
                    ProgressView()
                }
            }
            .navigationDestination(for: Document.self) { document in
                DocumentDetailView(document: document)
                    .navigationBarTitleDisplayMode(.inline)
//                    .navigationTitle(document.title)
//                    .navigationBarTitle(document.title)
            }
            .navigationTitle("Documents")
            .task {
                await store.fetch()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
