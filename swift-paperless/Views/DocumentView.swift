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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .foregroundColor(.white)
            .background(LinearGradient(colors: [
                    Color.blue, Color(uiColor: .blue.darker())
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing))
            .clipShape(Capsule())
            .shadow(radius: 5)
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

    func load(clear: Bool, setLoading _setLoading: Bool = true) async {
        if _setLoading { await setLoading(to: true) }
        print("Load: \(store.filterState)")
        await store.fetchDocuments(clear: clear)
        print("Load complete")
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

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollView in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        if isLoading {
                            ProgressView()
                                .padding(15)
                                .scaleEffect(2)
                                .transition(.opacity)
                        }
                        LazyVStack(alignment: .leading) {
                            ForEach($store.documents, id: \.id) { $document in
                                NavigationLink(destination: {
                                    DocumentDetailView(document: $document)
                                        .navigationBarTitleDisplayMode(.inline)
                                }, label: {
                                    DocumentCell(document: document).task {
                                        let index = store.documents.firstIndex { $0 == document }
                                        if index == store.documents.count - 10 {
                                            //                                    if document == store.documents.last {
                                            Task {
                                                await load(clear: false, setLoading: false)
                                            }
                                        }
                                    }
                                    .contentShape(Rectangle())
                                })
                                .buttonStyle(.plain)
                                .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                            }
                        }
                        if store.documents.isEmpty && !isLoading && !initialLoad {
                            Text("No documents found")
                                .foregroundColor(.gray)
                                .transition(.opacity)
                        }
                    }

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

                    .task {
                        if initialLoad {
                            await load(clear: true)
                            initialLoad = false
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
                            .frame(width: 20, height: 20)
                        })
                        .modifier(PillButton())
                    }
                    .padding()
//                    }
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
    }
}

struct DocumentView_Previews: PreviewProvider {
    static let store = DocumentStore()

    static var previews: some View {
        DocumentView()
            .environmentObject(store)
    }
}
