//
//  SavedViewEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.04.23.
//

import DataModel
import Networking
import SwiftUI
import os

public struct SavedViewEditView<Element>: View where Element: SavedViewProtocol {
  @State private var savedView: Element
  public var onSave: ((Element) throws -> Void)?

  private var saveLabel: String

  private var editable: Bool { onSave != nil && savedView.userCanChange }

  private var valid: Bool {
    !savedView.name.isEmpty && editable
  }

  @Environment(DocumentStore.self) private var store

  public init(
    element savedView: Element,
    onSave: ((Element) throws -> Void)?
  ) {
    _savedView = State(initialValue: savedView)
    self.onSave = onSave
    saveLabel = String(localized: .app(.save))
  }

  private func load() async {
    guard let sv = savedView as? SavedView else {
      // nothing to do
      return
    }

    guard store.repository.supports(feature: .savedViewNewVisibility) else {
      return
    }

    // pull visibility settings from ui settings
    savedView.showInSidebar = store.settings.savedViews.sidebarViewsVisibleIds.contains(sv.id)
    savedView.showOnDashboard = store.settings.savedViews.dashboardViewsVisibleIds.contains(sv.id)
  }

  private func localizedName(for field: SortField) -> String {
    field.localizedName(customFields: store.customFields)
  }

  public var body: some View {
    Form {
      Section(String(localized: .app(.properties))) {
        TextField(String(localized: .app(.title)), text: $savedView.name)
          .clearable($savedView.name)

        Toggle(
          String(localized: .app(.savedViewShowOnDashboard)),
          isOn: $savedView.showOnDashboard)

        Toggle(
          String(localized: .app(.savedViewShowInSidebar)), isOn: $savedView.showInSidebar
        )
      }
      .disabled(!editable)

      Section(String(localized: .app(.sorting))) {
        Picker(String(localized: .app(.sortBy)), selection: $savedView.sortField) {
          ForEach(SortField.allCases, id: \.rawValue) { v in
            Text(localizedName(for: v)).tag(v)
          }
        }

        Picker(String(localized: .app(.sortOrder)), selection: $savedView.sortOrder) {
          Text(DataModel.SortOrder.ascending.localizedName)
            .tag(DataModel.SortOrder.ascending)
          Text(DataModel.SortOrder.descending.localizedName)
            .tag(DataModel.SortOrder.descending)
        }
      }
      .disabled(!editable)

      if store.repository.supports(feature: .savedViewPermissions) {
        Section {
          NavigationLink(.permissions(.title)) {
            PermissionsEditView(object: $savedView)
              .disabled(!editable)
          }
        }
        .disabled(!editable)
      }
    }

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button(String(localized: .app(.save))) {
          do {
            try onSave?(savedView)
          } catch {
            Logger.shared.error("Save saved view error: \(error)")
          }
        }
        .disabled(!valid)
        .bold()
      }
    }

    .task {
      await load()
    }

  }
}

extension SavedViewEditView where Element == ProtoSavedView {
  public init(onSave: @escaping (Element) throws -> Void) {
    self.init(element: ProtoSavedView(), onSave: onSave)
    saveLabel = String(localized: .app(.add))
  }
}

public struct EditSavedView_Previews: PreviewProvider {
  public struct Container: View {
    @State var view = ProtoSavedView(name: "")
    public var body: some View {
      SavedViewEditView(element: view, onSave: { _ in })
    }
  }

  public static var previews: some View {
    Container()
  }
}
