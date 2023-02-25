//
//  ContentView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 13.02.23.
//

import Combine
import QuickLook
import Semaphore
import SwiftUI

struct DocumentView: View {
    @StateObject private var store = DocumentStore()

//    @State var lastSearchString: String?
    @StateObject var searchDebounce = DebounceObject(delay: 0.1)

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    @State var initialLoad = true

    @State var isLoading = false

    let searchSemaphore = AsyncSemaphore(value: 1)

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
//        await searchSemaphore.wait()
//        defer { searchSemaphore.signal() }

//        if let last = lastSearchString {
//            if last.lowercased() == searchDebounce.debouncedText.lowercased() {
//                // skip search as it's the same as before
//                return
//            }
//        }

        var filterState = store.filterState
        filterState.searchText = query == "" ? nil : query
        store.setFilterState(to: filterState)

        isLoading = true
        await load(clear: true)
        isLoading = false
    }

    var body: some View {
        NavigationStack {
//            ScrollViewReader { _ in
            ScrollView {
                if isLoading {
                    ProgressView()
                }
//                EmptyView().id("documentsTop")
                // @TODO: Maybe switch back to list
                // Normal VStack doesn't work because it renders everything at once (instant paging)
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
                        //                        .listRowBackground(Color.clear)
                        //                        .listRowSeparatorTint(.clear)
                        //                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    }
                }.opacity(isLoading ? 0.5 : 1.0)
            }
            //                if store.isLoading && store.currentPage == 1 {
            //                    ProgressView()
            //                }
            .toolbar {
                //                ToolbarItem(placement: .principal) {
                //                    Text("Hi")
                //                }
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
//                    scrollView.scrollTo("documentsTop")
                isLoading = true
                Task {
                    await load(clear: true)
                }
                isLoading = false
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
                withAnimation {
//                        scrollView.scrollTo("documentsTop")
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
                    await load(clear: true)
                }
            }

//                .onChange(of: searchDebounce.text) { value in
//                    if value == "" {
//                        searchSuggestions = []
//
//                        if let last = lastSearchString {
//                            if last.lowercased() != searchDebounce.debouncedText.lowercased() {
//                                searchDebounce.debouncedText = ""
//                            }
//                        }
//                    }
//                }

            .onChange(of: searchDebounce.debouncedText) { _ in
                if searchDebounce.debouncedText == "" {
                    withAnimation {
//                            scrollView.scrollTo("documentsTop")
                    }
                }
                Task {
                    await updateSearchCompletion()

                    print("Change search to \(searchDebounce.debouncedText)")

                    if searchDebounce.debouncedText == "" {
                        await handleSearch(query: "")
//                            await load(clear: true)
                    }
                }

//                    print("initiate search for \(searchDebounce.debouncedText)")
//                    scrollView.scrollTo("documentsTop")
//                    Task {
//                        await handleSearch()
//                    }
            }
//            }
        }
        .environmentObject(store)
    }
}
