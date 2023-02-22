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

    @State var lastSearchString: String?
    @StateObject var searchDebounce = DebounceObject()

    @State var showFilterModal: Bool = false

    @State var searchSuggestions: [String] = []

    func loadInitial() async {
        store.isLoading = true
        // @TODO: Make HTTP requests concurrently
        async let _ = await store.fetchAllCorrespondents()
        async let _ = await store.fetchAllDocumentTypes()
        await store.fetchDocuments(searchText: searchDebounce.debouncedText == "" ? nil : searchDebounce.debouncedText, clear: true)
        store.isLoading = false
    }

    func loadNextPage() async {
        await store.fetchDocuments(searchText: searchDebounce.debouncedText == "" ? nil : searchDebounce.debouncedText, clear: false)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading) {
                    ForEach($store.documents, id: \.id) { $document in
                        NavigationLink(destination: {
                            DocumentDetailView(document: $document)
                                .navigationBarTitleDisplayMode(.inline)
                        }, label: {
                            DocumentCell(document: document).task {
                                if document == store.documents.last {
                                    await loadNextPage()
                                }
                            }
                        })
                        .buttonStyle(.plain)
                        .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
//                        .listRowBackground(Color.clear)
//                        .listRowSeparatorTint(.clear)
//                        .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    }
                }.opacity(store.isLoading ? 0.5 : 1.0)
            }
            .animation(.default, value: store.documents)
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
            .sheet(isPresented: $showFilterModal) { FilterView() }
            .task {
                if store.currentPage == 1 && store.documents.isEmpty {
                    await loadInitial()
                }
            }
            .refreshable {
                Task {
                    await loadInitial()
                }
            }
            .navigationTitle("Documents")
//            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchDebounce.text, placement: .automatic, suggestions: {
                ForEach(searchSuggestions, id: \.self) { v in
                    Text(v).searchCompletion(v)
                }
            })
            .onChange(of: searchDebounce.text) { value in
                if value == "" {
                    searchSuggestions = []

                    if let last = lastSearchString {
                        if last.lowercased() != searchDebounce.debouncedText.lowercased() {
                            searchDebounce.debouncedText = ""
                        }
                    }
                }
            }
            .onChange(of: searchDebounce.debouncedText) { _ in
                if searchDebounce.debouncedText == "" {
                    searchSuggestions = []
                }
                else {
                    Task {
                        searchSuggestions = await getSearchCompletion(term: searchDebounce.debouncedText)
                    }
                }
                if let last = lastSearchString {
                    if last.lowercased() == searchDebounce.debouncedText.lowercased() {
                        // skip search as it's the same as before
                        return
                    }
                }

                Task {
                    store.isLoading = true
                    await loadInitial()
                    lastSearchString = searchDebounce.debouncedText
                    store.isLoading = false
                }
            }
        }
        .environmentObject(store)
    }
}
