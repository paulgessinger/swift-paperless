//
//  FilterBar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 10.04.23.
//

import Combine
import Foundation
import SwiftUI
import SwiftUINavigation

// MARK: FilterMenu

extension ProtoSavedView: Identifiable {
    var id: UInt { return 0 }
}

private struct FilterMenu<Content: View>: View {
    @EnvironmentObject private var store: DocumentStore
    @Binding var filterState: FilterState
    @ViewBuilder var label: () -> Content

    @State private var savedView: ProtoSavedView? = nil

    var body: some View {
        VStack {
            Menu {
                Text("Saved views")
                if !store.savedViews.isEmpty {
                    ForEach(store.savedViews.map { $0.value }.sorted { $0.id < $1.id }, id: \.id) { savedView in
                        if store.filterState.savedView == savedView.id {
                            Menu {
                                if store.filterState.modified {
                                    Button("Save") {}
                                    Button {
                                        store.filterState = .init(savedView: savedView)
                                    } label: {
                                        Label("Discard changes", systemImage: "arrow.counterclockwise")
                                    }
                                }
                                Button("Delete", role: .destructive) {}
                            } label: {
                                if store.filterState.modified {
                                    Label("\(savedView.name) (modified)", systemImage: "checkmark")
                                }
                                else {
                                    Label("\(savedView.name)", systemImage: "checkmark")
                                }
                            }
                        }
                        else {
                            Button {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    store.filterState = .init(savedView: savedView)
                                }
                            } label: {
                                Text("\(savedView.name)")
                            }
                        }
                    }
                }

                if filterState.filtering && (filterState.savedView == nil || filterState.modified) {
                    Button {
                        let proto = ProtoSavedView(name: "", filterRules: store.filterState.rules)

                        savedView = proto
                        //                    showSavedViewModal = true

                    } label: {
                        Label("Add new", systemImage: "plus.circle")
                    }
                }

                if filterState.filtering {
                    if !store.savedViews.isEmpty {
                        Divider()
                    }
                    Text("\(filterState.ruleCount) filter(s) applied")
                    Divider()
                    Button(role: .destructive) {
                        Haptics.shared.notification(.success)
                        withAnimation {
                            store.filterState.clear()
                            filterState.clear()
                        }
                    } label: {
                        Label("Clear filters", systemImage: "xmark")
                    }
                }

            } label: {
                label()
            }
        }

        .sheet(unwrapping: self.$savedView) { $view in
            EditSavedView(savedView: $view) {
                guard let savedView = savedView else {
                    fatalError("Saved view did not return")
                }

                Task {
                    do {
                        try await store.createSavedView(savedView)
                    }
                    catch {
                        print(error)
                    }
                }
            }
        }
    }
}

// MARK: Element View

private struct Element<Label: View>: View {
    @ViewBuilder var label: () -> Label
    var active: Bool
    var action: () -> Void
    var chevron = true

    @State private var pressed = false

    var body: some View {
        Pill(active: active, chevron: chevron, label: label)
            .onTapGesture {
                Haptics.shared.impact(style: .light)
                action()
                Task {
                    pressed = true
                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation {
                        pressed = false
                    }
                }
            }
            .opacity(pressed ? 0.7 : 1.0)
    }
}

private struct Pill<Label: View>: View {
    var active: Bool
    var chevron = true
    @ViewBuilder var label: () -> Label

    var body: some View {
        HStack {
            label()
            if chevron {
                Image(systemName: "chevron.down")
            }
        }
        .frame(minHeight: 25)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background {
            Capsule()
                .fill(Color("ElementBackground"))
        }
        .overlay(
            Capsule()
                .strokeBorder(active ? Color.accentColor : Color("ElementBorder"),
                              lineWidth: 1))
        .foregroundColor(active ? Color.accentColor : Color.primary)
        .if(active) { view in view.bold() }
    }
}

struct FilterBar: View {
    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var showTags = false
    @State private var showDocumentType = false
    @State private var showCorrespondent = false

    private enum ModalMode {
        case tags
        case correspondent
        case documentType
    }

    @State private var filterState = FilterState()

    @State var offset = CGSize()
    @State var menuWidth = 0.0
    @State var filterMenuHit = false

    private struct Modal<Content: View>: View {
        @EnvironmentObject private var store: DocumentStore
        @Environment(\.dismiss) private var dismiss

        var title: String
        @Binding var filterState: FilterState
        var onDismiss: () -> Void = {}
        @ViewBuilder var content: () -> Content

        var body: some View {
            NavigationStack {
                VStack {
                    content()
                }
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                            store.filterState = filterState
                            onDismiss()
                        }
                    }
                }
            }
        }
    }

    private struct CircleCounter: View {
        enum Mode {
            case include
            case exclude
        }

        var value: Int
        var mode = Mode.include

        private var color: Color {
            switch mode {
            case .include:
                return Color.accentColor
            case .exclude:
                return Color.red
            }
        }

        var body: some View {
            Text("\(value)")
                .foregroundColor(.white)
                .if(value == 1) { view in view.padding(5).padding(.leading, -1) }
                .if(value > 1) { view in view.padding(5) }
                .frame(minWidth: 20, minHeight: 20)
                .background(Circle().fill(color))
        }
    }

    // MARK: present()

    private func present(_ mode: ModalMode) {
//        impact.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            switch mode {
            case .tags:
                showTags = true
            case .correspondent:
                showCorrespondent = true
            case .documentType:
                showDocumentType = true
            }
        }
    }

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Pill(active: filterState.filtering || filterState.savedView != nil, chevron: false) {
                        Label("Filtering", systemImage: "line.3.horizontal.decrease")
                            .labelStyle(.iconOnly)
                        if let savedViewId = filterState.savedView,
                           let savedView = store.savedViews[savedViewId],
                           !filterState.modified
                        {
                            Text("\(savedView.name)")
                        }
                        else if filterState.ruleCount > 0 {
                            CircleCounter(value: filterState.ruleCount)
                        }
                    }
                    .opacity(filterMenuHit ? 0.5 : 1.0)
                    .overlay {
                        GeometryReader { geo in
                            FilterMenu(filterState: $filterState) {
                                Color.clear
                                    .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                        .onTapGesture {
                            Task {
                                Haptics.shared.prepare()
                                Haptics.shared.impact(style: .light)
                                filterMenuHit = true
                                try? await Task.sleep(for: .seconds(0.3))
                                withAnimation { filterMenuHit = false }
                            }
                        }
                    }

                    .onChange(of: offset) { _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            withAnimation {
                                menuWidth = offset.width
                            }
                        }
                    }

                    Element(label: {
                        switch filterState.tags {
                        case .any:
                            Text("Tags")
                        case .notAssigned:
                            Text("None")
                        case .allOf(let include, let exclude):
                            let count = include.count + exclude.count
                            if count == 1 {
                                if let i = include.first, let name = store.tags[i]?.name {
                                    Text(name)
                                }
                                else if let i = exclude.first, let name = store.tags[i]?.name {
                                    Label("Exclude", systemImage: "xmark")
                                        .labelStyle(.iconOnly)
                                    Text("\(name)")
                                }
                                else {
                                    Text("1 tag")
                                        .redacted(reason: .placeholder)
                                }
                            }
                            else {
                                if !include.isEmpty, !exclude.isEmpty {
                                    CircleCounter(value: include.count, mode: .include)
                                    Text("/")
                                    CircleCounter(value: exclude.count, mode: .exclude)
                                }
                                else if !include.isEmpty {
                                    CircleCounter(value: count, mode: .include)
                                }
                                else {
                                    CircleCounter(value: count, mode: .exclude)
                                }
                                Text("Tags")
                            }
                        case .anyOf(let ids):
                            if ids.count == 1 {
                                if let name = store.tags[ids.first!]?.name {
                                    Text(name)
                                }
                                else {
                                    Text("1 tag")
                                        .redacted(reason: .placeholder)
                                }
                            }
                            else {
                                CircleCounter(value: ids.count)
                                Text("Tags")
                            }
                        }
                    }, active: filterState.tags != .any) {
                        //                    if showTags {
                        //                        print("IS ALREADY TRUE")
                        //                        showTags = false
                        //                    }
                        ////                    DispatchQueue.main.async {
                        ////                    Task {
                        //                    showTags = true
                        ////                    }
                        ////                    }
                        present(.tags)
                    }

                    Element(label: {
                        switch filterState.documentType {
                        case .any:
                            Text("Document Type")
                        case .notAssigned:
                            Text("None")
                        case .only(let id):
                            if let name = store.documentTypes[id]?.name {
                                Text(name)
                            }
                            else {
                                Text("1 document type")
                                    .redacted(reason: .placeholder)
                            }
                        }
                    }, active: filterState.documentType != .any) { present(.documentType) }

                    Element(label: {
                        switch filterState.correspondent {
                        case .any:
                            Text("Correspondent")
                        case .notAssigned:
                            Text("None")
                        case .only(let id):
                            if let name = store.correspondents[id]?.name {
                                Text(name)
                            }
                            else {
                                Text("1 correspondent")
                                    .redacted(reason: .placeholder)
                            }
                        }
                    }, active: filterState.correspondent != .any) { present(.correspondent) }

                    Divider()

                    Element(label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                            .labelStyle(.iconOnly)
                    }, active: false, action: {})
                }
                .padding(.horizontal)
                .foregroundColor(.primary)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(0.5))
            withAnimation {
                filterState = store.filterState
            }
        }
        .padding(.bottom, 10)
        .overlay(
            Rectangle()
                .fill(Color("Divider"))
                .frame(maxWidth: .infinity, maxHeight: 1),
            alignment: .bottom
        )
        .padding(.bottom, -8)

        // MARK: Sheets

        .sheet(isPresented: $showTags) {
            Modal(title: "Tags", filterState: $filterState) {
                TagFilterView(
                    selectedTags: $filterState.tags)
            }
        }

        .sheet(isPresented: $showDocumentType) {
            Modal(title: "Document Type", filterState: $filterState) {
                CommonPicker(
                    selection: $filterState.documentType,
                    elements: store.documentTypes.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }

        .sheet(isPresented: $showCorrespondent) {
            Modal(title: "Correspondent", filterState: $filterState) {
                CommonPicker(
                    selection: $filterState.correspondent,
                    elements: store.correspondents.sorted {
                        $0.value.name < $1.value.name
                    }.map { ($0.value.id, $0.value.name) }
                )
            }
        }

//        .onChange(of: store.filterState) { value in
        .onReceive(store.filterStatePublisher) { value in
            DispatchQueue.main.async {
                withAnimation {
                    filterState = value
                }
            }
        }
    }
}
