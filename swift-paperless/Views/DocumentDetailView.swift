//
//  DocumentDetailView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

private enum DownloadState {
    case initial
    case loading
    case loaded(PDFThumbnail)
    case error
}

struct DocumentPreview: View {
    var store: DocumentStore

    var document: Document

    @State private var download: DownloadState = .initial
    @State private var fullPreview: Image? = nil

    func loadFullPreview() async {
        guard let url = await store.repository.download(documentID: document.id) else {
            print("Failure to download document")
            return
        }
        guard let image = pdfPreview(url: url) else {
            print("Failure to generate preview")
            return
        }
        await MainActor.run {
            print("Have full preview")
            withAnimation {
                fullPreview = image
            }
        }
    }

    var body: some View {
        VStack {
            if let fullPreview = fullPreview {
                fullPreview
                    .resizable()
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .scaledToFill()
                    .shadow(color: Color(white: 0.9), radius: 5)
            }
            else {
                AuthAsyncImage(image: {
                    let image = await store.repository.thumbnail(document: document)
                    Task.detached {
                        try? await Task.sleep(for: .seconds(0.2))
                        await loadFullPreview()
                    }
                    return image
                }) {
                    image in
                    image
                        .resizable()
                        .scaledToFill()
                        //                                .frame(width: 100, height: 100, alignment: .top)
                        .cornerRadius(10)
                        .overlay(RoundedRectangle(cornerRadius: 10)
                            .stroke(.gray, lineWidth: 1))
                } placeholder: {
                    Rectangle()
                        .fill(Color(white: 0.8))
                        .cornerRadius(10)
                        .scaledToFit()
                        .overlay(ProgressView())
                }
                .blur(radius: 5)
            }

//            switch download {
//            case .loading, .initial, .loaded:
//                HStack {
//                    Spacer()
//                    ProgressView()
//                    Spacer()
//                }
//                .frame(width: 400, height: 400*1.4)
//            case .error:
//                HStack {
//                    Spacer()
//                    Label("Unable to load preview", systemImage: "eye.slash")
//                        .labelStyle(.iconOnly)
//                        .imageScale(.large)
//
//                    Spacer()
//                }
//                .frame(width: 400, height: 400*1.4)
//
//            case let .ready(_, image):
//                image
//                    .resizable()
//                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.gray, lineWidth: 1))
//                    .clipShape(RoundedRectangle(cornerRadius: 5))
//                    .scaledToFill()
//                    .shadow(color: Color(white: 0.9), radius: 5)
//            }
        }

        .task {
//            switch download {
//            case .initial:
//                download = .loading
//                guard let url = await store.repository.download(documentID: document.id) else {
//                    download = .error
//                    return
//                }
//                download = .loaded(url)
//                guard let image = pdfPreview(url: url) else {
//                    download = .error
//                    return
//                }
//                withAnimation {
//                    download = .ready(url, image)
//                }
//
//            default:
//                break
//            }
        }
    }
}

struct DocumentDetailView: View {
    @EnvironmentObject private var store: DocumentStore

    @State var document: Document
    var navPath: Binding<NavigationPath>?

    @State private var editing = false
    @State private var download: DownloadState = .initial
    @State private var previewUrl: URL?

    @State private var tags: [Tag] = []

    @State private var relatedDocuments: [Document]? = nil

    @Environment(\.colorScheme) private var colorScheme

    private func loadDocument() async {
        switch download {
        case .initial:
            download = .loading
            guard let url = await store.repository.download(documentID: document.id) else {
                download = .error
                return
            }
            guard let view = PDFThumbnail(file: url) else {
                download = .error
                return
            }
            withAnimation {
                download = .loaded(view)
            }

        default:
            break
        }
    }

    private struct Aspect: View {
        var label: String
        var systemImage: String

        @ScaledMetric(relativeTo: .body) var imageWidth = 20.0

        init(_ label: String, systemImage: String) {
            self.label = label
            self.systemImage = systemImage
        }

        var body: some View {
            HStack {
                Image(systemName: systemImage)
                    .frame(width: imageWidth, alignment: .leading)
                Text(label)
            }
        }
    }

    var gray: Color {
        if colorScheme == .dark {
            return Color.secondarySystemGroupedBackground
        }
        else {
            return Color.systemGroupedBackground
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading) {
                    Text(document.title)
                        .font(.title)
                        .bold()
                        .padding(.bottom)
                    HStack(alignment: .top, spacing: 25) {
                        VStack(alignment: .leading) {
                            if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                Aspect(name, systemImage: "person")
                                    .foregroundColor(Color.accentColor)
                            }
                            else {
                                Aspect("Not assigned", systemImage: "person")
                                    .foregroundColor(Color.gray)
                                    .opacity(0.5)
                            }

                            if let id = document.documentType, let name = store.documentTypes[id]?.name {
                                Aspect(name, systemImage: "doc")
                                    .foregroundColor(Color.orange)
                            }
                            else {
                                Aspect("Not assigned", systemImage: "doc")
                                    .foregroundColor(Color.gray)
                                    .opacity(0.5)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading) {
                            Aspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

                            if let id = document.storagePath, let name = store.storagePaths[id]?.name {
                                Aspect(name, systemImage: "archivebox")
                            }
                            else {
                                Aspect("Default", systemImage: "archivebox")
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }

                    TagsView(tags: document.tags.compactMap { store.tags[$0] })
                }
                .padding()

                VStack {
                    switch download {
                    case .loading, .initial:

                        HStack {
                            AuthAsyncImage {
                                await store.repository.thumbnail(document: document)
                            } content: { image in
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .blur(radius: 5)
                            }
                            placeholder: {
                                ProgressView()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .aspectRatio(0.75, contentMode: .fit)
                            }
                        }
                    case .error:
                        HStack {
                            Spacer()
                            Label("Unable to load preview", systemImage: "eye.slash")
                                .labelStyle(.iconOnly)
                                .imageScale(.large)

                            Spacer()
                        }

                    case let .loaded(view):
                        view
                            .background(.white)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(.gray, lineWidth: 1))
                .shadow(color: Color("ImageShadow"), radius: 15)
                .padding()

                .onTapGesture {
                    if case let .loaded(view) = download {
                        previewUrl = view.file
                    }
                }
            }

            .refreshable {
                if let document = await store.document(id: document.id) {
                    self.document = document
                }
            }
        }

        .quickLookPreview($previewUrl)

//                if let related = relatedDocuments {
//                    Group {
//                        Divider()
//                        HStack {
//                            Spacer()
//                            Text("Related documents")
//                                .foregroundColor(.gray)
//                            Spacer()
//                        }
//                        ForEach(related) { _ in Text("Doc") }
//                    }
//                    .transition(
//                        .opacity.combined(with: .move(edge: .bottom)))
//                }

        .navigationBarTitleDisplayMode(.inline)

        .task {
            await loadDocument()
        }

        .onChange(of: store.documents) { _ in
            if let document = store.documents[document.id] {
                self.document = document
            }
        }

        .toolbar {
            Button("Edit") {
                editing.toggle()
            }
        }

        .sheet(isPresented: $editing) {
            DocumentEditView(document: $document, navPath: navPath)
        }
    }
}

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        NavigationStack {
            VStack {
                if let document = document {
                    DocumentDetailView(document: document, navPath: $navPath)
                }
            }
            .task {
                document = await store.document(id: 1)
            }
        }
    }
}

struct DocumentDetailsView_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        PreviewHelper()
            .environmentObject(store)
    }
}
