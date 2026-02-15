//
//  Untitled.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.01.26.
//

import SwiftUI

enum FilterBarComponent: String, CaseIterable, Codable {
  case tags
  case documentType
  case correspondent
  case storagePath
  case permissions
  case customFields
  case asn
  case date

  var localizedName: LocalizedStringResource {
    switch self {
    case .tags: .localizable(.tags)
    case .documentType: .localizable(.documentType)
    case .correspondent: .localizable(.correspondent)
    case .storagePath: .localizable(.storagePath)
    case .permissions: .localizable(.permissions)
    case .customFields: .localizable(.customFields)
    case .asn: .localizable(.asn)
    case .date: .localizable(.dateFilterTitle)
    }
  }
}

enum FilterBarConfiguration: Equatable, Codable {
  case `default`
  case configured([FilterBarComponent])
}

extension FilterBarConfiguration {
  fileprivate var components: [FilterBarComponent] {
    switch self {
    case .default:
      return FilterBarComponent.allCases
    case .configured(let components):
      return components
    }
  }

  fileprivate func contains(_ component: FilterBarComponent) -> Bool {
    components.contains(component)
  }

  fileprivate static func fromComponents(_ components: [FilterBarComponent])
    -> FilterBarConfiguration
  {
    if components == FilterBarComponent.allCases {
      return .default
    }
    return .configured(components)
  }
}

extension [FilterBarComponent: Bool] {
  fileprivate subscript(comp: FilterBarComponent) -> Bool {
    get {
      self[comp] ?? false
    }
    set {
      self[comp] = newValue
    }
  }
}

struct FilterBarConfigView: View {
  @State private var enabledStatus: [FilterBarComponent: Bool]
  @State private var editMode: EditMode = .inactive

  @Namespace private var namespace

  init() {
    let enabled = AppSettings.shared.filterBarConfiguration
    let status = FilterBarComponent.allCases.reduce(
      into: [FilterBarComponent: Bool](), { $0[$1] = enabled.contains($1) })
    _enabledStatus = State(initialValue: status)
  }

  private var disabledComponents: [FilterBarComponent] {
    FilterBarComponent.allCases.filter { enabledStatus[$0] ?? false == false }
  }

  private func reset() {
    AppSettings.shared.filterBarConfiguration = FilterBarConfiguration.default
    enabledStatus = FilterBarComponent.allCases.reduce(
      into: [FilterBarComponent: Bool](), { $0[$1] = true })
  }

  private var isDefault: Bool {
    switch AppSettings.shared.filterBarConfiguration {
    case .default:
      return true
    case .configured(let components):
      return components == FilterBarComponent.allCases
    }
  }

  private var configuredComponents: Binding<[FilterBarComponent]> {
    Binding(
      get: { AppSettings.shared.filterBarConfiguration.components },
      set: { newValue in
        AppSettings.shared.filterBarConfiguration = FilterBarConfiguration.fromComponents(newValue)
      }
    )
  }

  var body: some View {
    List {
      Section {
        ForEach(configuredComponents, id: \.self, editActions: [.move]) { $comp in
          if editMode == .inactive {
            Toggle(isOn: $enabledStatus[comp]) {
              Text(comp.localizedName)
            }
            .id(comp.rawValue)
          } else {
            Text(comp.localizedName)
          }
        }
      }

      Section {
        ForEach(disabledComponents, id: \.self) { comp in
          if editMode == .inactive {
            Toggle(isOn: $enabledStatus[comp]) {
              Text(comp.localizedName)
            }
            .id(comp.rawValue)
          } else {
            Text(comp.localizedName)
          }
        }
      }

      if !isDefault {
        Button {
          reset()
        } label: {
          Label(
            localized: .settings(.resetFilterConfiguration), systemImage: "arrow.counterclockwise"
          )
          .frame(maxWidth: .infinity, alignment: .center)
        }
      }
    }

    .animation(.spring, value: AppSettings.shared.filterBarConfiguration)
    .animation(.spring, value: disabledComponents)
    .animation(.default, value: editMode)

    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        CustomEditButton()
      }
    }

    .onChange(of: enabledStatus) {
      Task {
        try? await Task.sleep(for: .seconds(0.3))
        var components = AppSettings.shared.filterBarConfiguration.components
        components = components.filter { enabledStatus[$0] ?? false }
        components += FilterBarComponent.allCases.filter {
          !components.contains($0) && enabledStatus[$0] ?? true
        }
        AppSettings.shared.filterBarConfiguration = FilterBarConfiguration.fromComponents(
          components)
      }
    }

    .environment(\.editMode, $editMode)
  }
}

#Preview {
  NavigationStack {
    FilterBarConfigView()
  }
}
