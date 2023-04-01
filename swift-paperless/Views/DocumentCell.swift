//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

private protocol Loadable {
    var name: String { get }
}

extension Correspondent: Loadable {}
extension DocumentType: Loadable {}

private enum LoadingState<T: Loadable>: Equatable {
    static func == (lhs: LoadingState<T>, rhs: LoadingState<T>) -> Bool {
        switch lhs {
        case .none:
            switch rhs {
            case .none:
                return true
            default:
                return false
            }
        case .loading:
            switch rhs {
            case .loading:
                return true
            default:
                return false
            }
        case .value:
            switch rhs {
            case .value:
                return true
            default:
                return false
            }
        }
    }

    case none
    case loading
    case value(T)

    func name() -> String? {
        switch self {
        case .none:
            return nil
        case .loading:
            return "      "
        case .value(let t):
            return t.name
        }
    }
}

struct DocumentCell: View {
    @EnvironmentObject var store: DocumentStore

    var document: Document
    var correspondent: Correspondent? = nil
    var documentType: DocumentType? = nil
    var tags: [Tag] = []

    init(document: Document, store: DocumentStore) {
        self.document = document
//        self.correspondent = nil
//        self.documentType = nil
//        self.tags = []
        self.correspondent = self.document.correspondent.flatMap { store.correspondents[$0] }
        self.documentType = self.document.documentType.flatMap { store.documentTypes[$0] }
        self.tags = self.document.tags.compactMap { store.tags[$0] }
    }

    var body: some View {
        HStack(alignment: .top) {
            AuthAsyncImage(image: {
                await store.repository.thumbnail(document: document)
            }) {
                image in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: 100, height: 100, alignment: .top)
                    .cornerRadius(10)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .stroke(.gray, lineWidth: 1))
            } placeholder: {
                Rectangle()
                    .fill(.gray)
                    .cornerRadius(10)
                    .scaledToFit()
                    .overlay(ProgressView())
            }
            .frame(width: 100, height: 100)
            .shadow(color: Color("ImageShadow"), radius: 5)

            VStack(alignment: .leading) {
                if let name = correspondent?.name {
                    Text("\(name):")
                        .foregroundColor(.accentColor)
                        .id("correspondent")
                }
                Text("\(document.title)").bold()

                if let name = documentType?.name {
                    Text(name)
                        .fixedSize()
                        .foregroundColor(Color.orange)
                }

                Text(document.created, style: .date)

                TagsView(tags: tags)
                    .padding(0)
                    .transition(.opacity)
            }
            .padding(.horizontal, 5)
        }
    }
}

private struct HelperView: View {
    @EnvironmentObject var store: DocumentStore
    @State var documents = [Document]()

    var body: some View {
        VStack {
            ForEach(documents.prefix(5), id: \.id) { document in
                DocumentCell(document: document, store: store)
                    .padding()
            }
            Spacer()
        }
        .task {
            documents = await store.fetchDocuments(clear: false)
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        HelperView()
            .environmentObject(store)
    }
}
