//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import SwiftUI

struct DocumentView: View {
    @StateObject private var store = DocumentStore()

    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    func load(clear: Bool) async {
        async let _ = await store.fetchAllCorrespondents()
        async let _ = await store.fetchAllDocumentTypes()
        print("Load")
        await store.fetchDocuments(clear: clear)
        print("Load complete")
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
        store.setFilterState(to: filterState)

        await setLoading(to: true)
        await load(clear: true)
        await setLoading(to: false)
    }

    func setLoading(to value: Bool) async {
        withAnimation {
            isLoading = value
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollView in
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
                                            await load(clear: false)
                                        }
                                    }
                                }
                            })
                            .buttonStyle(.plain)
                            .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: { showFilterModal.toggle() }) {
                            Label("Filter", systemImage:
                                //                            "line.3.horizontal.decrease.circle.fill" :
                                "line.3.horizontal.decrease.circle")
                        }
                    }
                }
                .navigationTitle("Documents")

                .refreshable {
                    Task {
                        await setLoading(to: true)
                        await load(clear: true)
                        await setLoading(to: false)
                    }
                }

                .searchable(text: $searchDebounce.text, placement: .automatic) {
                    ForEach(searchSuggestions, id: \.self) { v in
                        Text(v).searchCompletion(v)
                    }
                }

                .animation(.default, value: store.documents)

                .onSubmit(of: .search) {
                    print("Search submit: \(searchDebounce.text)")
                    if searchDebounce.text == store.filterState.searchText {
                        return
                    }
                    if store.documents.count > 0 {
                        withAnimation {
                            scrollView.scrollTo(store.documents[0].id, anchor: .top)
                        }
                        store.clearDocuments()
                    }
                    Task {
                        await handleSearch(query: searchDebounce.text)
                    }
                }

                .sheet(isPresented: $showFilterModal, onDismiss: {
                    print("Filter updated \(store.filterState)")
//                    scrollView.scrollTo("documentsTop")
//                    Task {
//                        await load(clear: true)
//                    }
                }) {
                    FilterView()
                        .environmentObject(store)
                }

                .task {
                    if initialLoad {
                        initialLoad = false
                        await setLoading(to: true)
                        await load(clear: true)
                        await setLoading(to: false)
                    }
                }

                .onChange(of: searchDebounce.debouncedText) { _ in
                    if searchDebounce.debouncedText == "" {
                        if store.documents.count > 0 {
                            withAnimation {
                                scrollView.scrollTo(store.documents[0].id, anchor: .top)
                            }

                            store.clearDocuments()
                        }
                    }
                    Task {
                        await updateSearchCompletion()

                        print("Change search to \(searchDebounce.debouncedText)")

                        if searchDebounce.debouncedText == "" {
                            await handleSearch(query: "")
                        }
                    }
                }
            }
        }
        .environmentObject(store)
    }
}
