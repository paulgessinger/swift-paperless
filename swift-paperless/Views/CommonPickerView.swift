//
//  CommonPickerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

struct CommonPicker: View {
    @Binding var selection: FilterState.Filter
    var elements: [(UInt, String)]

    var filterMode = true

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    func row(_ label: String, value: FilterState.Filter) -> some View {
        return HStack {
            Button(action: { Task { selection = value } }) {
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

    private func filter(name: String) -> Bool {
        if searchDebounce.debouncedText.isEmpty { return true }
        if let _ = name.range(of: searchDebounce.debouncedText, options: .caseInsensitive) {
            return true
        }
        else {
            return false
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchDebounce.text)
                .transition(.opacity)
                .padding(.horizontal)
                .padding(.vertical, 2)
            Form {
                Section {
                    if filterMode {
                        row("Any", value: FilterState.Filter.any)
                    }
                    row(filterMode ? "Not assigned" : "None", value: FilterState.Filter.notAssigned)
                }
                Section {
                    ForEach(elements.filter { filter(name: $0.1) },
                            id: \.0)
                    { id, name in
                        row(name, value: FilterState.Filter.only(id: id))
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }
    }
}

protocol Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Self]> { get }
    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol

    var id: UInt { get }
    var name: String { get }
}

extension Correspondent: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: Correspondent]> { \.correspondents }

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.correspondent
    }
}

extension DocumentType: Pickable {
    static var storePath: KeyPath<DocumentStore, [UInt: DocumentType]> { \.documentTypes }

    static func documentPath<D>(_ type: D.Type) -> WritableKeyPath<D, UInt?> where D: DocumentProtocol {
        return \.documentType
    }
}

struct CommonPickerEdit<Element, D>: View where Element: Pickable, D: DocumentProtocol {
    @EnvironmentObject var store: DocumentStore

    @Binding var document: D

    @StateObject private var searchDebounce = DebounceObject(delay: 0.1)

    @State private var showNone = true

    private func elements() -> [(UInt, String)] {
        let allDict = store[keyPath: Element.storePath]

        let all = allDict.sorted {
            $0.value.name < $1.value.name
        }.map { ($0.value.id, $0.value.name) }

        if searchDebounce.debouncedText.isEmpty { return all }

        return all.filter { $0.1.range(of: searchDebounce.debouncedText, options: .caseInsensitive) != nil }
    }

    init(_ type: Element.Type, document: Binding<D>) {
        self._document = document
    }

    func row(_ label: String, value: UInt?) -> some View {
        return HStack {
            Button(action: {
                // set new value
                document[keyPath: Element.documentPath(D.self)] = value
            }) {
                Text(label)
            }
            .foregroundColor(.primary)
            Spacer()
            if document[keyPath: Element.documentPath(D.self)] == value {
                Label("Active", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
            }
        }
    }

    var body: some View {
        VStack {
            SearchBarView(text: $searchDebounce.text)
                .transition(.opacity)
                .padding(.horizontal)
                .padding(.vertical, 2)
            Form {
                if showNone {
                    Section {
                        row("None", value: nil)
                    }
                }
                Section {
                    ForEach(elements(), id: \.0) { id, name in
                        row(name, value: id)
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(Color("Divider"))
                    .frame(maxWidth: .infinity, maxHeight: 1),
                alignment: .top
            )
        }
        .onChange(of: searchDebounce.debouncedText) { value in
            withAnimation {
                showNone = value.isEmpty
            }
        }
    }
}

struct CommonPickerEditCorrespondent_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentLoader(id: 1) { document in
            CommonPickerEdit(
                Correspondent.self,
                document: document
            )
        }
        .environmentObject(store)
    }
}

struct CommonPickerEditDocumentType_Previews: PreviewProvider {
    @StateObject static var store = DocumentStore(repository: PreviewRepository())

    static var previews: some View {
        DocumentLoader(id: 1) { document in
            CommonPickerEdit(
                DocumentType.self,
                document: document
            )
        }
        .environmentObject(store)
    }
}
