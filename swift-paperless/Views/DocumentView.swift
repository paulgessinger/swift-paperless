//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import SwiftUI

import AsyncAlgorithms

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

struct DocumentView: View {
    @EnvironmentObject var store: DocumentStore
    @EnvironmentObject var connectionManager: ConnectionManager

    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var documents: [Document] = []

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    @State var loadingMore = false

    @State var filterState = FilterState()

    @State var refreshRequested = false

    @StateObject var nav = NavigationCoordinator()

    func load(clear: Bool) async {
        if clear {
            await store.fetchAll()
        }
        let new = await store.fetchDocuments(clear: clear)

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

    func cell(document: Document) -> some View {
        Group {
            NavigationLink(value:
                NavigationState.detail(document: document)
            ) {
                DocumentCell(document: document)
                    .contentShape(Rectangle())
            }

            .buttonStyle(.plain)
            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))

            if document != documents.last {
                Divider()
                    .padding(.horizontal)
            }
        }
    }

    @State private var scrollOffset = ThrottleObject(value: CGPoint(), delay: 0.1)

    var body: some View {
        NavigationStack(path: $nav.path) {
            ZStack(alignment: .bottomTrailing) {
                OffsetObservingScrollView(offset: $scrollOffset.value) {
                    VStack(alignment: .leading) {
                        ForEach(documents.prefix(100).compactMap { store.documents[$0.id] }) { document in
                            cell(document: document)
                        }
                        LazyVStack(alignment: .leading) {
                            ForEach(documents.dropFirst(100).compactMap { store.documents[$0.id] }) { document in
                                cell(document: document)
                                    .task {
                                        let hasMore = await store.hasMoreDocuments()
                                        print("Check more: has: \(hasMore), #doc \(documents.count)")
                                        if let index = documents.firstIndex(where: { $0 == document }) {
                                            if index >= documents.count - 10 && !loadingMore && hasMore {
                                                print("LOAD MORE")
                                                Task {
                                                    loadingMore = true
                                                    await load(clear: false)
                                                    loadingMore = false
                                                }
                                            }
                                        }
                                    }
                            }
                        }

                        if !isLoading && !initialLoad {
                            Divider().padding()
                            HStack {
                                Spacer()
                                let text = (documents.isEmpty ? "No documents" : (documents.count == 1 ? "1 document" : "\(documents.count) documents")) + " found"
                                Text(text)
                                    .foregroundColor(.gray)
                                    .transition(.opacity)
                                Spacer()
                            }
                        }
                    }
                }

                .navigationDestination(for: NavigationState.self, destination: { nav in
                    if case let .detail(doc) = nav {
                        DocumentDetailView(document: doc)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                })

                .refreshable {
                    // @TODO: Refresh animation here is broken if this modifies state that triggers rerender
                    if isLoading { return }
                    refreshRequested = true
                }

                // Decoupled refresh when scroll is back
                .onReceive(scrollOffset.publisher) { offset in
                    if offset.y >= -0.0 && refreshRequested {
                        refreshRequested = false
                        Task {
                            isLoading = true
                            await load(clear: true)
                            isLoading = false
                        }
                    }
                }

                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            Button("Logout") {
                                connectionManager.logout()
                            }
                        } label: {
                            Label("Menu", systemImage: "ellipsis.circle")
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .transition(.scale)
                            }
//                            else {
//                                Button(action: {
//                                    Task {
//                                        isLoading = true
//                                        await load(clear: true)
//                                        isLoading = false
//                                    }
//                                }) {
//                                    Label("Reload", systemImage: "arrow.counterclockwise")
//                                }
//                                .transition(.scale)
//                            }
                        }
//                        .animation(.default, value: isLoading)
                    }
                }
                .navigationTitle("Documents")

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
                    //                    DispatchQueue.main.async {
                    Task {
                        // wait for a short bit while the modal is still
                        // open to let the animation finish
                        if showFilterModal {
                            do { try await Task.sleep(for: .seconds(0.5)) } catch {}
                        }
                        await load(clear: true)
                    }
                    //                    }
                }

                .onChange(of: searchDebounce.debouncedText) { _ in
                    if searchDebounce.debouncedText == "" {
                        //                            scrollToTop(scrollView: scrollView)
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
