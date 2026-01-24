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

private extension [FilterBarComponent: Bool] {
  subscript(comp: FilterBarComponent) -> Bool {
    get {
      self[comp] ?? false
    }
    set {
      self[comp] = newValue
    }
  }
}

struct FilterBarConfigView : View {
  @State private var enabledStatus: [FilterBarComponent: Bool]
  @State private var editMode: EditMode = .inactive
  
  @ObservedObject private var appSettings = AppSettings.shared

  @Namespace private var namespace
  
  init() {
    // @TODO: Read this from settingsa
//    _enabledComponents = State(initialValue: appSettings.filterBarConfiguration)
    
    let enabled = AppSettings.shared.filterBarConfiguration
    let status = FilterBarComponent.allCases.reduce(into: [FilterBarComponent: Bool](), { $0[$1] = enabled.contains($1) })
    _enabledStatus = State(initialValue: status)
  }
  
  private var disabledComponents: [FilterBarComponent] {
    FilterBarComponent.allCases.filter { enabledStatus[$0] ?? false == false }
  }
  
  private func reset() {
    appSettings.filterBarConfiguration = FilterBarComponent.allCases
    enabledStatus = FilterBarComponent.allCases.reduce(into: [FilterBarComponent: Bool](), { $0[$1] = true })
  }
  
  private var isDefault: Bool {
    appSettings.filterBarConfiguration == FilterBarComponent.allCases
  }
  
  var body: some View {
      List {
        Section {
          ForEach($appSettings.filterBarConfiguration, id: \.self, editActions: [.move]) { $comp in
            if editMode == .inactive {
              Toggle(isOn: $enabledStatus[comp]) {
                Text(comp.localizedName)
              }
              .id(comp.rawValue)
            }
            else {
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
            }
            else {
              Text(comp.localizedName)
            }
          }
        }
        
        if !isDefault {
          Button {
            reset()
          }
          label: {
            Label(localized: .settings(.resetFilterConfiguration), systemImage: "arrow.counterclockwise")
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
      }
    
      .animation(.spring, value: appSettings.filterBarConfiguration)
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
          appSettings.filterBarConfiguration = appSettings.filterBarConfiguration.filter { enabledStatus[$0] ?? false }
          appSettings.filterBarConfiguration += FilterBarComponent.allCases.filter { !appSettings.filterBarConfiguration.contains($0) && enabledStatus[$0] ?? true }
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
