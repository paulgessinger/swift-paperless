//
//  FilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

private struct PreviewHelper<Content: View>: View {
    @EnvironmentObject var store: DocumentStore
    @State var loaded = false

    let content: (DocumentStore) -> Content

    init(@ViewBuilder content: @escaping (DocumentStore) -> Content) {
        self.content = content
    }

    var body: some View {
        VStack {
            if loaded {
                content(store)
            }
        }
        .task {
            await store.fetchAll()
            loaded = true
        }
    }
}

struct DocumentTypeView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())
    @State static var filterState = FilterState()

    static var previews: some View {
        PreviewHelper { store in
            CommonPicker(
                selection: $filterState.documentType,
                elements: store.documentTypes.sorted {
                    $0.value.name < $1.value.name
                }.map { ($0.value.id, $0.value.name) }
            )
        }
        .environmentObject(store)
    }
}

struct CorrespondentView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())
    @State static var filterState = FilterState()

    static var previews: some View {
        PreviewHelper { store in
            CommonPicker(
                selection: $filterState.correspondent,
                elements: store.correspondents.sorted {
                    $0.value.name < $1.value.name
                }.map { ($0.value.id, $0.value.name) }
            )
        }
        .environmentObject(store)
    }
}

// MARK: - FilterView

struct FilterView: View {
    @Environment(\.dismiss) var dismiss

    @EnvironmentObject var store: DocumentStore

    @State private var modified: Bool = false

    enum Active {
        case correspondent
        case documentType
        case tag
    }

    @State var activeTab = Active.tag
    @State var showClear = false

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                VStack(alignment: .center) {
                    Picker("Tab", selection: $activeTab) {
                        Label("Tag", systemImage: "tag.fill")
                            .labelStyle(.iconOnly)
                            .tag(Active.tag)
                        Label("Correspondent", systemImage: "person.fill")
                            .labelStyle(.iconOnly)
                            .tag(Active.correspondent)
                        Label("Document type", systemImage: "doc.fill")
                            .labelStyle(.iconOnly)
                            .tag(Active.documentType)
                    }
                    .frame(width: 0.6 * geo.size.width)
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    Group {
                        if activeTab == .correspondent {
                            CommonPicker(
                                selection: $store.filterState.correspondent,
                                elements: store.correspondents.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }
                        else if activeTab == .documentType {
                            CommonPicker(
                                selection: $store.filterState.documentType,
                                elements: store.documentTypes.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }
                        else if activeTab == .tag {
                            TagFilterView(
                                selectedTags: $store.filterState.tags)
                        }
                    }
                    .navigationTitle("Filter")
                    .navigationBarTitleDisplayMode(.inline)

                    .onChange(of: store.filterState) { value in
                        DispatchQueue.main.async {
                            showClear = value != FilterState()
                        }
                    }

                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Clear") {
                                store.filterState = FilterState()
                                dismiss()
                            }
                            .opacity(showClear ? 1 : 0)
                        }

                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                dismiss()
                            }.bold()
                        }
                    }
                }
                .frame(width: geo.size.width)
            }
            .interactiveDismissDisabled(modified)
        }
        .task {
            self.showClear = store.filterState != FilterState()
        }
    }
}

struct FilterView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        VStack {
            FilterView()
        }
        .environmentObject(store)
    }
}
