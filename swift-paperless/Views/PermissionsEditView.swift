//
//  PermissionsEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.07.2024.
//

import Flow
import os
import SwiftUI

private struct ElementPicker<T: Identifiable>: View where T.ID == UInt {
    @Binding var selected: [UInt]
    let storePath: KeyPath<DocumentStore, [UInt: T]>
    let name: KeyPath<T, String>

    private var elements: [T] {
        store[keyPath: storePath].values
            .sorted(by: { $0[keyPath: name] < $1[keyPath: name] })
    }

    @EnvironmentObject private var store: DocumentStore

    var body: some View {
        List {
            ForEach(elements, id: \.id) { element in
                Button {
                    if selected.contains(element.id) {
                        selected = selected.filter { $0 != element.id }
                    } else {
                        selected.append(element.id)
                    }
                } label: {
                    HStack {
                        Text(element[keyPath: name])
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(.primary)

                        if selected.contains(element.id) {
                            Label(localized: .localizable(.elementIsSelected),
                                  systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.accent)
                        }
                    }
                }
                .tint(.primary)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct PermissionsEditView<Element>: View where Element: PermissionsModel {
    @Binding var element: Element

    @EnvironmentObject private var store: DocumentStore

    private var permissions: Permissions {
        element.permissions ?? .init()
    }

    private func binding(kind: WritableKeyPath<Permissions, Permissions.Set>,
                         element: WritableKeyPath<Permissions.Set, [UInt]>) -> Binding<[UInt]>
    {
        Binding<[UInt]>(get: {
            permissions[keyPath: kind][keyPath: element]
        }, set: {
            var permissions = permissions
            permissions[keyPath: kind][keyPath: element] = $0
            self.element.permissions = permissions
        })
    }

    private var viewUsers: Binding<[UInt]> {
        binding(kind: \.view, element: \.users)
    }

    private var viewGroups: Binding<[UInt]> {
        binding(kind: \.view, element: \.groups)
    }

    private var changeUsers: Binding<[UInt]> {
        binding(kind: \.change, element: \.users)
    }

    private var changeGroups: Binding<[UInt]> {
        binding(kind: \.change, element: \.groups)
    }

    private var users: [User] {
        store.users
            .values
            .sorted(by: { $0.username < $1.username })
    }

    private func nameList<T>(_ ids: [UInt],
                             storePath: KeyPath<DocumentStore, [UInt: T]>,
                             name: KeyPath<T, String>) -> Text
    {
        var result = Text("")

        for (i, id) in ids.enumerated() {
            if i > 0 {
                result = result + Text(", ")
            }
            if let element = store[keyPath: storePath][id] {
                result = result + Text(element[keyPath: name])
            } else {
                result = result + Text(.permissions(.private))
                    .italic()
            }
        }
        return result
    }

    private func userList(_ ids: [UInt]) -> Text {
        nameList(ids, storePath: \.users, name: \.username)
    }

    private func groupList(_ ids: [UInt]) -> Text {
        nameList(ids, storePath: \.groups, name: \.name)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Picker(.permissions(.owner), selection: $element.owner) {
                        Text(.permissions(.noOwner))
                            .tag(nil as UInt?)
                        ForEach(users, id: \.id) { user in
                            Text(user.username)
                                .tag(user.id as UInt?)
                        }
                    }
                }
            } footer: {
                Text(.permissions(.unownedDescription))
            }
            .pickerStyle(.navigationLink)

            Section(.permissions(.view)) {
                NavigationLink {
                    ElementPicker(selected: viewUsers,
                                  storePath: \.users,
                                  name: \.username)
                        .navigationTitle(.permissions(.users))
                } label: {
                    LabeledContent {
                        userList(permissions.view.users)
                    } label: {
                        Text(.permissions(.users))
                    }
                }

                NavigationLink {
                    ElementPicker(selected: viewGroups,
                                  storePath: \.groups,
                                  name: \.name)
                        .navigationTitle(.permissions(.groups))
                } label: {
                    LabeledContent {
                        groupList(permissions.view.groups)
                    } label: {
                        Text(.permissions(.groups))
                    }
                }
            }

            Section(.permissions(.change)) {
                NavigationLink {
                    ElementPicker(selected: changeUsers,
                                  storePath: \.users,
                                  name: \.username)
                        .navigationTitle(.permissions(.users))
                } label: {
                    LabeledContent {
                        userList(permissions.change.users)
                    } label: {
                        Text(.permissions(.users))
                    }
                }

                NavigationLink {
                    ElementPicker(selected: changeGroups,
                                  storePath: \.groups,
                                  name: \.name)
                        .navigationTitle(.permissions(.groups))
                } label: {
                    LabeledContent {
                        groupList(permissions.change.groups)
                    } label: {
                        Text(.permissions(.groups))
                    }
                }
            }
        }
        .task {
            do {
                // update users and groups just in case
                async let users: Void = try await store.fetchAllUsers()
                async let groups: Void = try await store.fetchAllGroups()

                _ = try await (users, groups)
            } catch is CancellationError {}
            catch {
                Logger.shared.error("Error loading users for permissions editing: \(error)")
            }
        }
    }
}

// - MARK: Previews

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        NavigationStack {
            if document != nil {
                PermissionsEditView(element: Binding($document)!)
            }
        }
        .task {
            document = try? await store.document(id: 1)
            document?.permissions = .init(view: .init(users: [1]), change: .init(groups: [2]))
            guard document != nil else {
                fatalError()
            }
        }
    }
}

#Preview {
//    @Previewable
    @StateObject var store = DocumentStore(repository: PreviewRepository())
//    @Previewable
    @StateObject var errorController = ErrorController()

    return PreviewHelper()
        .environmentObject(store)
        .environmentObject(errorController)
}
