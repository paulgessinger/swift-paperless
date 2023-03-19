//
//  DocumentCell.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI
import WrappingStack

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

    @State private var correspondent: LoadingState<Correspondent> = .loading
    @State private var documentType: LoadingState<DocumentType> = .loading
    @State private var tags: [Tag]? = nil

    @State private var initial = true
    @State private var isLoading = false

    @Namespace private var animation

    func load() async {
//        isLoading = true
        correspondent = .loading
        documentType = .loading

        async let tagResult = store.getTags(document.tags)
        async let corrResult = document.correspondent == nil ? nil : store.getCorrespondent(id: document.correspondent!)
        async let typeResult = document.documentType == nil ? nil : store.getDocumentType(id: document.documentType!)

        let (tagR, corrR, typeR) = await (tagResult, corrResult, typeResult)

        if let (cached, corr) = corrR {
            if cached {
                correspondent = .value(corr)
            }
            else {
                withAnimation {
                    correspondent = .value(corr)
                }
            }
        }
        else {
            correspondent = .none
        }

        if let (cached, type) = typeR {
            if cached {
                documentType = .value(type)
            }
            else {
                withAnimation {
                    documentType = .value(type)
                }
            }
        }
        else {
            documentType = .none
        }

        let (cached, tags) = tagR
        if cached {
            self.tags = tags
        }
        else {
            withAnimation {
                self.tags = tags
            }
        }

//        withAnimation {
        ////            tags = tagR
        ////            correspondent = corrR?.1
        ////            documentType = typeR?.1
//            isLoading = false
//        }
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

            VStack(alignment: .leading) {
                if let name = correspondent.name() {
//                    var reason: RedactionReasons = []
//                    if case .loading = correspondent {
//                        reason = .placeholder
//                    }
                    Text("\(name):")
                        .foregroundColor(.accentColor)
                        .id("correspondent")
                        .if(correspondent == .loading) { view in
                            view.redacted(reason: .placeholder)
                        }
                }
                Text("\(document.title)").bold()

                if let name = documentType.name() {
                    Text(name)
                        .fixedSize()
                        .foregroundColor(Color.orange)
                        .redacted(reason: documentType == .loading ? .placeholder : [])
                        .transition(.opacity)
                }

                Text(document.created, style: .date)

                TagsView(tags: tags ?? [])
                    .redacted(reason: tags == nil ? .placeholder : [])
                    .padding(0)
                    .transition(.opacity)
            }
            .padding(.horizontal, 5)
        }
        .task {
            await load()
        }
    }
}

struct DocumentCell_Previews: PreviewProvider {
    static let store = DocumentStore(repository: NullRepository())

    static var documents: [Document] = [
        .init(id: 1715,
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 2, correspondent: 2,
              created: Date.now, tags: [1, 2]),
        .init(id: 1714,
              title: "Official ESTA Application Website, U.S. Customs and Border Protection",
              documentType: 1, correspondent: nil,
              created: Date.now, tags: [1, 2]),
    ]

    static var previews: some View {
        VStack {
            ForEach(documents, id: \.id) { document in
                DocumentCell(document: document)
                    .padding()
            }
            Spacer()
        }
        .environmentObject(store)
    }
}
