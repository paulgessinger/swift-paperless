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

// MARK: - CommonPicker

struct CommonPicker: View {
    @Binding var selection: FilterState.Filter
    var elements: [(UInt, String)]

    func row(_ label: String, value: FilterState.Filter) -> some View {
        return HStack {
            Button(action: { selection = value }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if selection == value {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    var body: some View {
        return Form {
            Section {
                row("Any", value: FilterState.Filter.any)
                row("Not assigned", value: FilterState.Filter.notAssigned)

                ForEach(elements, id: \.0) { id, name in
                    row(name, value: FilterState.Filter.only(id: id))
                }
            }
        }
    }
}

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

    @State var filterState: FilterState = .init()

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

    init(filterState: FilterState,
         correspondents: [UInt: Correspondent],
         documentTypes: [UInt: DocumentType],
         tags: [UInt: Tag])
    {
        self._filterState = State(initialValue: filterState)
        self.correspondents = correspondents
        self.documentTypes = documentTypes
        self.tags = tags
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
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Clear", role: .cancel) {
                                store.filterState = FilterState()
                                dismiss()
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

enum PreviewModel {
    static let correspondents: [UInt: Correspondent] = [
        1: Correspondent(id: 1, documentCount: 0, isInsensitive: false, name: "Corr 1", slug: "corr-1"),
        2: Correspondent(id: 2, documentCount: 0, isInsensitive: false, name: "Corr 2", slug: "corr-2")
    ]

    static let documentTypes: [UInt: DocumentType] = [
        1: DocumentType(id: 1, name: "Type A", slug: "type-a"),
        2: DocumentType(id: 2, name: "Type B", slug: "type-b")
    ]

    static let tags: [UInt: Tag] = {
        var out: [UInt: Tag] = [:]
        let colors: [Color] = [
            .red,
            .blue,
            .gray,
            .green,
            .yellow,
            .orange,
            .brown,
            .indigo,
            .cyan,
            .mint
        ]

        for i in 1 ... 20 {
            out[UInt(i)] = Tag(id: UInt(i), isInboxTag: false, name: "Tag \(i)", slug: "tag-\(i)", color: colors[i % colors.count], textColor: Color.white)
        }
        return out
    }()
}

struct FilterView_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore()

    static var previews: some View {
        HStack {
            FilterView(
                filterState: store.filterState,
                correspondents: PreviewModel.correspondents,
                documentTypes: PreviewModel.documentTypes,
                tags: PreviewModel.tags
            )
        }
        .environmentObject(store)
    }
}
