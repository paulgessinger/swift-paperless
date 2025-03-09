//
//  PermissionsEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.07.2024.
//

import Common
import DataModel
import Flow
import Networking
import os
import SwiftUI

private struct ElementPicker<T>: View
    where T: Identifiable & LocalizedResource, T.ID == UInt
{
    @Binding var selected: [UInt]
    let storePath: KeyPath<DocumentStore, [UInt: T]>
    let name: KeyPath<T, String>

    @EnvironmentObject private var store: DocumentStore
    private var displayElements: [T] {
        store[keyPath: storePath]
            .values
            .sorted(by: { $0[keyPath: name] < $1[keyPath: name] })
    }

    private var resource: UserPermissions.Resource? {
        UserPermissions.Resource(for: T.self)
    }

    private var permissions: UserPermissions.PermissionSet {
        guard let resource else {
            return .empty
        }

        return store.permissions[resource]
    }

    private struct NoPermissionsView: View {
        var body: some View {
            ContentUnavailableView(String(localized: .permissions(.noViewPermissionsDisplayTitle)),
                                   systemImage: "lock.fill",
                                   description: Text(T.localizedNoViewPermissions))
        }
    }

    var body: some View {
        List {
            if !permissions.test(.view) {
                NoPermissionsView()
            } else {
                ForEach(displayElements, id: \.id) { element in
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
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
struct PermissionsEditView<Element>: View where Element: PermissionsModel {
    @Binding var element: Element

    @State private var ownerUser: User?

//    init(element: Binding<Element>) {
//        // @TODO: The initialization needs to go into `task`
//        self._element = element
//    }

    private func initialize() async {
        do {
            // update users and groups just in case
            async let users: Void = try await store.fetchAllUsers()
            async let groups: Void = try await store.fetchAllGroups()

            _ = try await (users, groups)
        } catch is CancellationError {}
        catch {
            Logger.shared.error("Error loading users for permissions editing: \(error)")
        }
        if let owner = element.owner {
            ownerUser = store.users[owner] ?? User(id: owner, isSuperUser: false, username: .permissions(.private))
        }
    }

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
                if T.self == User.self, let currentUser = store.currentUser, id == currentUser.id {
                    result = result + Text(.permissions(.userYouLabel(currentUser.username)))
                        .italic()
                } else {
                    result = result + Text(.permissions(.private))
                        .italic()
                }
            }
        }
        return result
    }

    private func userLabel(_ ids: [UInt]) -> some View {
        LabeledContent {
            nameList(ids, storePath: \.users, name: \.username)
        } label: {
            Text(.permissions(.users))
        }
    }

    private func groupLabel(_ ids: [UInt]) -> some View {
        LabeledContent {
            nameList(ids, storePath: \.groups, name: \.name)
        } label: {
            Text(.permissions(.groups))
        }
    }

    private var users: [User] {
        store.users.values.sorted { $0.username < $1.username }
    }

    // @TODO: Check edge cases for when logged in user can't see any users (we inject themselves)
    // - can only set read write perms for themselves
    // - can only set owner to themselves or nobody

    @ViewBuilder
    private var ownerPicker: some View {
        if !store.permissions.test(.view, for: .user) {
            Picker(.permissions(.owner), selection: $element.owner) {
                Text(.permissions(.noOwner))
                    .tag(nil as UInt?)
                if let currentUser = store.currentUser {
                    Text(.permissions(.userYouLabel(currentUser.username)))
                        .tag(currentUser.id as UInt?)
                }

                if let owner = element.owner, owner != store.currentUser?.id, let ownerUser {
                    Text(ownerUser.username)
                        .tag(owner as UInt?)
                }
            }
        } else {
            Picker(.permissions(.owner), selection: $element.owner) {
                Text(.permissions(.noOwner))
                    .tag(nil as UInt?)
                ForEach(users, id: \.id) { user in
                    Text(user.username)
                        .tag(user.id as UInt?)
                }
            }
        }
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    ownerPicker
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
                    userLabel(permissions.view.users)
                }

                NavigationLink {
                    ElementPicker(selected: viewGroups,
                                  storePath: \.groups,
                                  name: \.name)
                        .navigationTitle(.permissions(.groups))
                } label: {
                    groupLabel(permissions.view.groups)
                }
            }

            Section {
                NavigationLink {
                    ElementPicker(selected: changeUsers,
                                  storePath: \.users,
                                  name: \.username)
                        .navigationTitle(.permissions(.users))
                } label: {
                    userLabel(permissions.change.users)
                }

                NavigationLink {
                    ElementPicker(selected: changeGroups,
                                  storePath: \.groups,
                                  name: \.name)
                        .navigationTitle(.permissions(.groups))
                } label: {
                    groupLabel(permissions.change.groups)
                }
            } header: {
                Text(.permissions(.change))
            } footer: {
                if !store.permissions.test(.view, for: .user) {
                    Text(.permissions(.privateDescription))
                }
            }
        }
        .task { await initialize() }
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
            do {
                let repository = store.repository as! TransientRepository
                await repository.addUser(User(id: 1, isSuperUser: false, username: "user"))
                await repository.addUser(User(id: 2, isSuperUser: false, username: "user 2"))
                await repository.addGroup(UserGroup(id: 1, name: "group 1"))
                try? await repository.login(userId: 1)
                await repository.set(permissions: .full {
                    $0.set(.view, to: false, for: .user)
                    $0.set(.view, to: false, for: .group)
                })
                try await store.fetchAll()
                print(store.users)
                document = try? await store.repository.create(document: ProtoDocument(title: "blubb"),
                                                              file: #URL("http://example.com"))

                document?.owner = 2
                document?.permissions = Permissions {
                    $0.view.users = [1, 2]
                    $0.view.groups = [1]

                    $0.change.users = [1, 2]
                    $0.change.groups = [1]
                }
                print(document!)
            } catch { print(error) }
        }
    }
}

#Preview {
    @Previewable
    @StateObject var store = DocumentStore(repository: TransientRepository())
    @Previewable
    @StateObject var errorController = ErrorController()

    return PreviewHelper()
        .environmentObject(store)
        .environmentObject(errorController)
}
