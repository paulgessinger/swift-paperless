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

public struct PermissionsView: View {
  public let userPermissions: UserPermissions

  /// False while `ui_settings` hasn't landed for the active server. The store
  /// hands out `.full` in that state so the rest of the app stays usable (see
  /// `DocumentStore.permissions`), but rendering that as a green matrix would
  /// report access the server never granted — so this screen, which *displays*
  /// the matrix rather than gating on it, shows every cell as unknown instead.
  public let isKnown: Bool

  public init(userPermissions: UserPermissions, isKnown: Bool = true) {
    self.userPermissions = userPermissions
    self.isKnown = isKnown
  }

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
    var known: Bool = true

    public var body: some View {
      if known {
        Label(
          localized: value ? .app(.yes) : .app(.no),
          systemImage: value ? "checkmark.circle.fill" : "xmark.circle.fill"
        )
        .labelStyle(.iconOnly)
        .foregroundStyle(value ? .green : .gray)
      } else {
        Image(systemName: "questionmark.circle.fill")
          .foregroundStyle(.secondary)
          .accessibilityLabel(String(localized: .permissions(.permissionsNotLoaded)))
      }
    }
  }

  public var body: some View {
    Form {
      if !isKnown {
        Section {
          Label {
            Text(.permissions(.permissionsNotLoaded))
          } icon: {
            Image(systemName: "questionmark.circle.fill")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }

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
            Value(value: userPermissions.test(.view, for: resource), known: isKnown)
            Value(value: userPermissions.test(.add, for: resource), known: isKnown)
            Value(value: userPermissions.test(.change, for: resource), known: isKnown)
            Value(value: userPermissions.test(.delete, for: resource), known: isKnown)
          }
        }
      }

      Button(String(localized: .permissions(.copySummary))) {
        // Mark an unloaded matrix in the copied text too — this lands in bug
        // reports, where an all-green `.full` stand-in would be read as fact.
        Pasteboard.general.string =
          isKnown
          ? userPermissions.matrix
          : "(not loaded from server; assuming full access)\n\(userPermissions.matrix)"
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

#Preview("Permissions view (not loaded)") {
  NavigationStack {
    PermissionsView(userPermissions: .full, isKnown: false)
  }
}
