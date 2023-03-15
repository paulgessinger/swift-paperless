//
//  FilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import SwiftUI

protocol Pickable {
    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {}
extension DocumentType: Pickable {}

struct DocumentTypeView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore()
    @State static var filterState = FilterState()

    static var previews: some View {
        HStack {
            CommonPicker(
                selection: $filterState.documentType,
                elements: PreviewModel.documentTypes.sorted {
                    $0.value.name < $1.value.name
                }.map { ($0.value.id, $0.value.name) }
            )
        }
        .environmentObject(store)
    }
}

struct CorrespondentView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore()
    @State static var filterState = FilterState()

    static var previews: some View {
        HStack {
            CommonPicker(
                selection: $filterState.correspondent,
                elements: PreviewModel.correspondents.sorted {
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

    private var correspondents: [UInt: Correspondent]
    private var documentTypes: [UInt: DocumentType]
    private var tags: [UInt: Tag]

    enum Active {
        case correspondent
        case documentType
        case tag
    }

    @State var activeTab = Active.tag
    @State var showClear = false

    init(correspondents: [UInt: Correspondent],
         documentTypes: [UInt: DocumentType],
         tags: [UInt: Tag])
    {
        self.correspondents = correspondents
        self.documentTypes = documentTypes
        self.tags = tags
//        if store.filterState != FilterState() {
//            self._showClear = State(initialValue: true)
//        }
    }

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
                                elements: correspondents.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }
                        else if activeTab == .documentType {
                            CommonPicker(
                                selection: $store.filterState.documentType,
                                elements: documentTypes.sorted {
                                    $0.value.name < $1.value.name
                                }.map { ($0.value.id, $0.value.name) }
                            )
                        }
                        else if activeTab == .tag {
                            TagSelectionView(tags: tags,
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
                            if showClear {
                                Button("Clear") {
                                    store.filterState = FilterState()
                                    dismiss()
                                }
                            }
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
    }
}

struct FilterView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore()

    static var previews: some View {
        HStack {
            FilterView(
                //                filterState: store.filterState,
                correspondents: PreviewModel.correspondents,
                documentTypes: PreviewModel.documentTypes,
                tags: PreviewModel.tags
            )
        }
        .environmentObject(store)
    }
}
