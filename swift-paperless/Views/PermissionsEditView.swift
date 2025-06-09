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

private struct ElementPicker<E, T>: View
    where T: Identifiable & LocalizedResource, T.ID == UInt, E: PermissionsModel
{
    // E: Anything that HAS permissions
    // T: User or Group

    // This is the OBJECT that will receive changes to its permissions property
    @Binding var object: E

    // kind: read or write
    let kind: WritableKeyPath<Permissions, Permissions.Set>
    // type: user os group
    let type: WritableKeyPath<Permissions.Set, [UInt]>
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

    private var selected: [UInt] {
        guard let perms = object.permissions else { return [] }
        return perms[keyPath: kind][keyPath: type]
    }

    private func set(selected: [UInt]) {
        var newPerms = object.permissions ?? Permissions()
        newPerms[keyPath: kind][keyPath: type] = selected
        object.permissions = newPerms
    }

    private func row(_ element: T) -> some View {
        Button {
            if selected.contains(element.id) {
                set(selected: selected.filter { $0 != element.id })
            } else {
                var updated = selected
                updated.append(element.id)
                set(selected: updated)
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

    var body: some View {
        List {
            if !permissions.test(.view) {
                NoPermissionsView()
            } else {
                ForEach(displayElements, id: \.id) { element in
                    row(element)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct OwnerPicker<Object>: View where Object: PermissionsModel {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: DocumentStore

    @Binding var object: Object

    private var users: [User] {
        store.users.values.sorted { $0.username < $1.username }
    }

    private struct Row: View {
        var isActive: Bool = false
        var label: () -> Text
        var action: (() -> Void)? = nil

        private var _label: some View {
            HStack {
                label()
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isActive {
                    Label(localized: .localizable(.elementIsSelected),
                          systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.accent)
                }
            }
        }

        var body: some View {
            if let action {
                Button {
                    action()
                } label: {
                    _label
                }
                .tint(.primary)
            } else {
                _label
            }
        }
    }

    var body: some View {
        Form {
            Row(isActive: object.owner == nil) {
                Text(.permissions(.noOwner))
            } action: {
                object.owner = nil
                dismiss()
            }

            if !store.permissions.test(.view, for: .user) {
                if let currentUser = store.currentUser {
                    Row(isActive: object.owner == currentUser.id) {
                        Text(.permissions(.userYouLabel(currentUser.username)))
                    } action: {
                        object.owner = currentUser.id
                        dismiss()
                    }
                }

                if object.owner != nil, object.owner != store.currentUser?.id {
                    Row(isActive: true) {
                        Text(.permissions(.private))
                    }
                }

            } else {
                ForEach(users, id: \.id) { user in
                    Row(isActive: user.id == object.owner) {
                        if let currentUser = store.currentUser, currentUser.id == user.id {
                            Text(.permissions(.userYouLabel(user.username)))
                        } else {
                            Text(user.username)
                        }
                    } action: {
                        object.owner = user.id
                        dismiss()
                    }
                }
            }
        }
    }
}

@MainActor
struct PermissionsEditView<Object>: View where Object: PermissionsModel {
    @Binding var object: Object
    @State var original: Object

    init(object: Binding<Object>) {
        _object = object
        _original = State(initialValue: object.wrappedValue)
    }

    private func initialize() async {
        do {
            // update users and groups just in case
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await store.fetchAllUsers() }
                group.addTask { try await store.fetchAllGroups() }

                while !group.isEmpty {
                    do {
                        try await group.next()
                    } catch is PermissionsError {
                        Logger.shared.debug("Permissions error fetching users and groups for permissions edit, suppressing")
                    } catch let error where error.isCancellationError {
                        Logger.shared.debug("Cancellation error fetching users and groups for permissions edit, suppressing")
                        continue
                    }
                }
            }
        } catch {
            Logger.shared.error("Error loading users / groups for permissions editing: \(error)")
        }
    }

    @EnvironmentObject private var store: DocumentStore

    private var permissions: Permissions {
        object.permissions ?? .init()
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

    private var ownerLabel: some View {
        LabeledContent {
            if object.owner == nil {
                return Text(.permissions(.noOwner))
            }

            if let currentUser = store.currentUser, object.owner == currentUser.id {
                return Text(.permissions(.userYouLabel(currentUser.username)))
            }

            if let owner = object.owner, let user = store.users[owner] {
                return Text(user.username)
            }

            return Text(.permissions(.private))
                .italic()
        } label: {
            Text(.permissions(.owner))
        }
    }

    private func warning(_ message: LocalizedStringResource) -> some View {
        Label(localized: message,
              systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
            .bold()
    }

    private func canNoLongerChange(_ user: User) -> Bool {
        user.canChange(original) && !user.canChange(object)
    }

    private func canNoLongerView(_ user: User) -> Bool {
        user.canView(original) && !user.canView(object)
    }

    var body: some View {
        Form {
            if let user = store.currentUser {
                if canNoLongerView(user), canNoLongerChange(user) {
                    warning(.permissions(.canNoLongerViewOrChange))
                } else if canNoLongerChange(user) {
                    warning(.permissions(.canNoLongerChange))
                } else if canNoLongerView(user) {
                    warning(.permissions(.canNoLongerView))
                }
            }

            Section {
                NavigationLink {
                    OwnerPicker(object: $object)
                } label: {
                    ownerLabel
                }
            } footer: {
                Text(.permissions(.unownedDescription))
            }
            .pickerStyle(.navigationLink)

            Section(.permissions(.view)) {
                NavigationLink {
                    ElementPicker(object: $object,
                                  kind: \.view,
                                  type: \.users,
                                  storePath: \.users,
                                  name: \.username)
                        .navigationTitle(.permissions(.users))
                } label: {
                    userLabel(permissions.view.users)
                }

                NavigationLink {
                    ElementPicker(object: $object,
                                  kind: \.view,
                                  type: \.groups,
                                  storePath: \.groups,
                                  name: \.name)
                        .navigationTitle(.permissions(.groups))
                } label: {
                    groupLabel(permissions.view.groups)
                }
            }

            Section {
                NavigationLink {
                    ElementPicker(object: $object,
                                  kind: \.change,
                                  type: \.users,
                                  storePath: \.users,
                                  name: \.username)
                        .navigationTitle(.permissions(.users))
                } label: {
                    userLabel(permissions.change.users)
                }

                NavigationLink {
                    ElementPicker(object: $object,
                                  kind: \.change,
                                  type: \.groups,
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
                PermissionsEditView(object: Binding($document)!)
            }
        }
        .task {
            do {
                let repository = store.repository as! TransientRepository
                await repository.addUser(User(id: 1, isSuperUser: false, username: "user", groups: [1]))
                await repository.addUser(User(id: 2, isSuperUser: false, username: "user 2"))
                await repository.addGroup(UserGroup(id: 1, name: "group 1"))
                await repository.addGroup(UserGroup(id: 2, name: "group 2"))
                try? await repository.login(userId: 1)
                await repository.set(permissions: .full {
                    $0.set(.view, to: true, for: .user)
                    $0.set(.view, to: true, for: .group)
                })
                try await store.fetchAll()
                print(store.users)
                try await store.repository.create(document: ProtoDocument(title: "blubb"),
                                                  file: #URL("http://example.com"), filename: "blubb.pdf")
                document = try await store.repository.documents(filter: .default).fetch(limit: 100_000).first { $0.title == "blubb" }

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
