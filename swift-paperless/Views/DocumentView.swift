//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import AsyncAlgorithms
import Combine
import QuickLook
import SwiftUI

struct SearchFilterBar<Content: View>: View {
    @Environment(\.isSearching) private var isSearching

    var content: () -> Content

    var body: some View {
        if isSearching {
            content()
        }
    }
}

struct PillButton: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 15)
            .padding(.vertical, 15)
            .foregroundColor(.white)
            .background(LinearGradient(colors: [
                    Color(uiColor: UIColor(Color("AccentColor")).ligher()),
                    Color.accentColor
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule())
            .shadow(radius: 5)
    }
}

enum NavigationState: Equatable, Hashable {
    case root
    case detail(document: Document)
}

class NavigationCoordinator: ObservableObject {
    var path = NavigationPath()

    func popToRoot() {
        path.removeLast(path.count)
    }
}

private func getCredentials(key: String) -> String {
    guard let path = Bundle.main.path(forResource: "Credentials", ofType: "plist") else {
        fatalError("Unable to load credentials plist")
    }

    guard let nsDictionary = NSDictionary(contentsOfFile: path) else {
        fatalError("Unable to load credentials plist")
    }

    guard let value = nsDictionary[key] as? String else {
        fatalError("Unable to load credentials plist")
    }

    return value
}

struct DocumentView: View {
    @StateObject private var store = DocumentStore(repository: ApiRepository(apiHost: getCredentials(key: "API_HOST"), apiToken: getCredentials(key: "API_TOKEN")))

    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var documents: [Document] = []

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    @State var filterState = FilterState()

    @StateObject var nav = NavigationCoordinator()

    func load(clear: Bool) async {
        async let x: () = store.fetchAll()
        let new = await store.fetchDocuments(clear: clear)

        await x

        if clear {
            withAnimation {
                documents = new
            }
        }
        else {
            withAnimation {
                documents += new
            }
        }
//        print("\(documents.count)")
    }

    func updateSearchCompletion() async {
        if searchDebounce.debouncedText == "" {
            searchSuggestions = []
        }
        else {
            searchSuggestions = await store.repository.getSearchCompletion(term: searchDebounce.debouncedText, limit: 10)
        }
    }

    func handleSearch(query: String) async {
        var filterState = store.filterState
        filterState.searchText = query == "" ? nil : query
        store.filterState = filterState

        isLoading = true
        await load(clear: true)
        isLoading = false
    }

    func scrollToTop(scrollView: ScrollViewProxy) {
        if store.documents.count > 0 {
            withAnimation {
                scrollView.scrollTo(documents[0].id, anchor: .top)
            }
        }
    }

    var body: some View {
        NavigationStack(path: $nav.path) {
            ScrollViewReader { scrollView in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
//                        if isLoading {
//                            ProgressView()
//                                .padding(15)
//                                .scaleEffect(1)
//                                .transition(.opacity)
//                        }
                        LazyVStack(alignment: .leading) {
                            ForEach(documents, id: \.id) { document in
//                                if let document = store.documents[document.id] {
                                NavigationLink(value:
                                    NavigationState.detail(document: document)
                                ) {
                                    // @TODO: Switch back to document from store
                                    //                                        DocumentCell(document: store.documents[document.id]!)
                                    DocumentCell(document: document)
                                        .task {
                                            if let index = documents.firstIndex(where: { $0 == document }) {
                                                if index >= documents.count - 10 {
                                                    Task {
                                                        await load(clear: false)
                                                    }
                                                }
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))

                                if document != documents.last {
                                    Divider()
                                        .padding(.horizontal)
                                }
//                                }
                            }
                        }
                        if documents.isEmpty && !isLoading && !initialLoad {
                            Text("No documents found")
                                .foregroundColor(.gray)
                                .transition(.opacity)
                        }
                    }

                    .navigationDestination(for: NavigationState.self, destination: { nav in
                        if case let .detail(doc) = nav {
                            DocumentDetailView(document: doc)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    })

                    // @TODO: Refresh animation here is broken :(
//                    .refreshable {
//                        Task {
//                            await load(clear: true)
//                        }
//                    }

                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Group {
                                if isLoading {
                                    ProgressView()
                                        .transition(.scale)
                                }
                                else {
                                    Button(action: {
                                        Task {
                                            isLoading = true
                                            await load(clear: true)
                                            isLoading = false
                                        }
                                    }) {
                                        Label("Reload", systemImage: "arrow.counterclockwise")
                                    }
                                    .transition(.scale)
                                }
                            }
                            .animation(.default, value: isLoading)
                        }
                    }
                    .navigationTitle("Documents")

                    .animation(.default, value: store.documents)

                    .sheet(isPresented: $showFilterModal, onDismiss: {}) {
                        FilterView(correspondents: store.correspondents,
                                   documentTypes: store.documentTypes,
                                   tags: store.tags)
                            .environmentObject(store)
//                            .presentationDetents([.large, .medium])
                    }

                    .onChange(of: store.documents) { _ in
                        documents = documents.compactMap { store.documents[$0.id] }
                    }

                    .onChange(of: store.filterState) { _ in
                        print("Filter updated \(store.filterState)")
                        Task {
                            store.clearDocuments()
                            await load(clear: true)
                        }
                    }

                    .onChange(of: searchDebounce.debouncedText) { _ in
                        if searchDebounce.debouncedText == "" {
                            scrollToTop(scrollView: scrollView)
                        }
                        Task {
                            await updateSearchCompletion()

                            print("Change search to \(searchDebounce.debouncedText)")

                            if searchDebounce.debouncedText == "" {
                                store.filterState.searchText = nil
                                await load(clear: true)
                            }
                        }
                    }

                    Button(action: {
                        let impactMed = UIImpactFeedbackGenerator(style: .medium)
                        impactMed.impactOccurred()

                        showFilterModal.toggle()

                    }) {
                        Label(title: { Text("Filter") }, icon: {
                            Image(systemName: store.filterState.filtering ?
                                "line.3.horizontal.decrease.circle.fill" :
                                "line.3.horizontal.decrease.circle"
                            )
                            .resizable()
                            .scaledToFit()
                            .frame(width: 25, height: 25)
                        })
                        .labelStyle(.iconOnly)
                        .modifier(PillButton())
                    }
                    .padding()
                }

                .task {
                    if initialLoad {
                        isLoading = true
                        await load(clear: true)
                        isLoading = false
                        initialLoad = false
                    }
                }

                .searchable(text: $searchDebounce.text,
                            placement: .automatic) {
                    ForEach(searchSuggestions, id: \.self) { v in
                        Text(v).searchCompletion(v)
                    }
                }

                .onSubmit(of: .search) {
                    print("Search submit: \(searchDebounce.text)")
                    if searchDebounce.text == store.filterState.searchText {
                        return
                    }
                    //            scrollToTop(scrollView: scrollView)
                    Task {
                        store.filterState.searchText = searchDebounce.text
                        await load(clear: true)
                    }
                }
            }
        }
        .environmentObject(store)
        .environmentObject(nav)
    }
}

struct DocumentView_Previews: PreviewProvider {
    static let store = DocumentStore(repository: NullRepository())

    static var previews: some View {
        DocumentView()
            .environmentObject(store)
    }
}
