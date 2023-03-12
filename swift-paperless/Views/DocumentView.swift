//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

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
    case detail(documentId: UInt)
}

class NavigationCoordinator: ObservableObject {
    @Published var path = NavigationPath()

    func popToRoot() {
        path.removeLast(path.count)
    }
}

struct DocumentView: View {
    @StateObject private var store = DocumentStore()

    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    @State var filterState = FilterState()

    @StateObject var navCoordinator = NavigationCoordinator()

    func load(clear: Bool, setLoading _setLoading: Bool = true) async {
        if _setLoading { await setLoading(to: true) }
//        _ = withAnimation {
//            Task {
        await store.fetchDocuments(clear: clear)
//            }
//        }
        if _setLoading { await setLoading(to: false) }
    }

    func updateSearchCompletion() async {
        if searchDebounce.debouncedText == "" {
            searchSuggestions = []
        }
        else {
            searchSuggestions = await getSearchCompletion(term: searchDebounce.debouncedText)
        }
    }

    func handleSearch(query: String) async {
        var filterState = store.filterState
        filterState.searchText = query == "" ? nil : query
        store.filterState = filterState

        await setLoading(to: true)
        await load(clear: true)
        await setLoading(to: false)
    }

    func setLoading(to value: Bool) async {
        withAnimation {
            isLoading = value
        }
    }

    func scrollToTop(scrollView: ScrollViewProxy) {
        if store.documents.count > 0 {
            withAnimation {
                scrollView.scrollTo(store.documents[0].id, anchor: .top)
            }
        }
    }

    func navigationDestinations(value: NavigationState) -> some View {
        switch value {
        case let .detail(id):
            for i in 0 ..< store.documents.count {
                let doc = $store.documents[i]
                if doc.id == id {
                    return AnyView(DocumentDetailView(document: doc)
                        .navigationBarTitleDisplayMode(.inline))
                }
            }
            fatalError("Logic error")
        default:
            return AnyView(Text("NOPE"))
        }
    }

    var body: some View {
        NavigationStack(path: $navCoordinator.path) {
            ScrollViewReader { scrollView in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        if isLoading {
                            ProgressView()
                                .padding(15)
                                .scaleEffect(1)
                                .transition(.opacity)
                        }
                        LazyVStack(alignment: .leading) {
                            ForEach($store.documents, id: \.id) { $document in
                                Button(action: {
                                    navCoordinator.path.append(NavigationState.detail(documentId: document.id))
                                }) {
                                    DocumentCell(document: document)
                                        .task {
                                            let index = store.documents.firstIndex { $0 == document }
                                            if index == store.documents.count - 10 {
                                                //                                    if document == store.documents.last {
                                                Task {
                                                    await load(clear: false, setLoading: false)
                                                }
                                            }
                                        }
                                        .contentShape(Rectangle())
                                }

                                .buttonStyle(.plain)
                                .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))

                                if document != store.documents.last {
                                    Divider()
                                        .padding(.horizontal)
                                }
                            }
                        }
                        if store.documents.isEmpty && !isLoading && !initialLoad {
                            Text("No documents found")
                                .foregroundColor(.gray)
                                .transition(.opacity)
                        }
                    }

                    // @TODO: This breaks 'refreshable' animation
                    .navigationDestination(for: NavigationState.self, destination: navigationDestinations)

                    .refreshable {
                        Task {
                            await load(clear: true)
                        }
                    }

                    .toolbar {
//                        ToolbarItem(placement: .navigationBarTrailing) {
//                            Button(action: { showFilterModal.toggle() }) {
//                                Label("Filter", systemImage:
//                                    store.filterState.filtering ?
//                                        "line.3.horizontal.decrease.circle.fill" :
//                                        "line.3.horizontal.decrease.circle")
//                            }
//                        }
                    }
                    .navigationTitle("Documents")

                    .animation(.default, value: store.documents)

                    .sheet(isPresented: $showFilterModal, onDismiss: {}) {
                        FilterView(filterState: store.filterState,
                                   correspondents: store.correspondents,
                                   documentTypes: store.documentTypes,
                                   tags: store.tags)
                            .environmentObject(store)
//                            .presentationDetents([.large, .medium])
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

//                    SearchFilterBar {
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
//                    }
                }

                .task {
                    if initialLoad {
                        await load(clear: true)
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
        .environmentObject(navCoordinator)
    }
}

struct DocumentView_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var previews: some View {
        DocumentView()
            .environmentObject(store)
    }
}
