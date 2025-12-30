//
//  PermissionsView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 08.06.25.
//

import Common
import DataModel
import SwiftUI

extension UserPermissions.Operation {
  fileprivate var icon: String {
    switch self {
    case .view: "eye"
    case .add: "plus"
    case .change: "pencil"
    case .delete: "trash"
    }
  }
}

struct PermissionsView: View {
  let userPermissions: UserPermissions

  private struct Row: Identifiable {
    var id: String { name }

    var name: String
    var perms: UserPermissions.PermissionSet
  }

  private var rows: [Row] {
    UserPermissions.Resource.allCases.map { resource in
      let permSet = userPermissions.get(for: resource)
      return Row(name: resource.rawValue, perms: permSet)
    }
  }

  private struct Value: View {
    let value: Bool

    var body: some View {
      Label(
        localized: value ? .localizable(.yes) : .localizable(.no),
        systemImage: value ? "checkmark.circle.fill" : "xmark.circle.fill"
      )
      .labelStyle(.iconOnly)
      .foregroundStyle(value ? .green : .gray)
    }
  }

  var body: some View {
    Form {
      Grid {
        GridRow {
          Text(.permissions(.resource))
            .frame(maxWidth: .infinity, alignment: .leading)

          ForEach(UserPermissions.Operation.allCases, id: \.self) { operation in
            Label(operation.localizedName, systemImage: operation.icon)
              .labelStyle(.iconOnly)
              .bold()
          }
        }
        Divider()

        ForEach(UserPermissions.Resource.allCases, id: \.self) { resource in
          GridRow {
            Text(resource.localizedName)
              .frame(maxWidth: .infinity, alignment: .leading)
            Value(value: userPermissions.test(.view, for: resource))
            Value(value: userPermissions.test(.add, for: resource))
            Value(value: userPermissions.test(.change, for: resource))
            Value(value: userPermissions.test(.delete, for: resource))
          }
        }
      }

      Button(String(localized: .permissions(.copySummary))) {
        Pasteboard.general.string = userPermissions.matrix
      }
    }
    .navigationTitle(String(localized: .permissions(.title)))
    .navigationBarTitleDisplayMode(.inline)
  }
}

#Preview("Permissions view") {
  let perms = UserPermissions.full.configure {
    $0.set(.view, to: false, for: .storagePath)
    $0.set(.change, to: false, for: .savedView)
  }

  NavigationStack {
    PermissionsView(userPermissions: perms)
  }
}
