//
//  AsnFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 02.01.26.
//

import DataModel
import SwiftUI

struct AsnFilterView: View {
  @Binding var query: FilterState.AsnFilter
  @State private var argument: String = ""
  @State private var mode: Mode = .any

  @Environment(\.dismiss) private var dismiss

  private enum Mode: CaseIterable, Equatable, Hashable {
    case any
    case isNull
    case isNotNull
    case equalTo
    case greaterThan
    case lessThan

    var label: LocalizedStringResource {
      switch self {
      case .any: .localizable(.asnFilterAny)
      case .isNull: .localizable(.asnFilterIsNull)
      case .isNotNull: .localizable(.asnFilterIsNotNull)
      case .equalTo: .localizable(.asnFilterEqualTo)
      case .greaterThan: .localizable(.asnFilterGreaterThan)
      case .lessThan: .localizable(.asnFilterLessThan)
      }
    }
  }

  private func initFromFilterState() {
    switch query {
    case .any:
      mode = .any
      argument = ""
    case .isNull:
      mode = .isNull
      argument = ""
    case .isNotNull:
      mode = .isNotNull
      argument = ""
    case .equalTo(let arg):
      mode = .equalTo
      argument = String(arg)
    case .greaterThan(let arg):
      mode = .greaterThan
      argument = String(arg)
    case .lessThan(let arg):
      mode = .lessThan
      argument = String(arg)
    }
  }

  private var isValid: Bool {
    switch mode {
    case .equalTo, .greaterThan, .lessThan:
      UInt(argument) != nil
    case .any, .isNull, .isNotNull:
      true
    }
  }

  private func confirm() {
    guard isValid else { return }

    switch mode {
    case .any:
      query = .any
    case .isNull:
      query = .isNull
    case .isNotNull:
      query = .isNotNull
    case .equalTo:
      query = .equalTo(UInt(argument) ?? 0)
    case .greaterThan:
      query = .greaterThan(UInt(argument) ?? 0)
    case .lessThan:
      query = .lessThan(UInt(argument) ?? 0)
    }

    dismiss()
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Picker(.localizable(.asnFilterModeSelectLabel), selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { mode in
              Text(mode.label)
                .tag(mode)
            }
          }

          if mode == .equalTo || mode == .greaterThan || mode == .lessThan {
            TextField(.localizable(.asnFilterArgumentLabel), text: $argument)
              .keyboardType(.numberPad)
          }
        }
      }
      .animation(.spring, value: mode)

      .toolbar {
        SaveButton(action: confirm)
          .backport.glassProminentButtonStyle(or: .automatic)
          .disabled(!isValid)
      }

      .navigationTitle(.localizable(.asn))
      .navigationBarTitleDisplayMode(.inline)

      .onAppear(perform: initFromFilterState)

      .onChange(of: argument) { oldValue, newValue in
        if newValue.isEmpty {
          return
        }

        if UInt(newValue) == nil {
          argument = oldValue
          return
        }
      }
    }
  }
}

struct AsnFilterDisplayView: View {
  let query: FilterState.AsnFilter

  @ViewBuilder
  private func label(_ loc: LocalizedStringResource, systemImage: String) -> some View {
    HStack {
      Image(systemName: systemImage)
      Text(loc)
    }
  }

  var body: some View {
    switch query {
    case .any:
      Text(.localizable(.asn))
    case .isNotNull:
      label(.localizable(.asn), systemImage: "number.circle")
    case .isNull:
      label(.localizable(.asn), systemImage: "nosign")
    case .equalTo(let arg):
      HStack {
        Text(.localizable(.asn))
        Image(systemName: "equal.circle")
        Text("\(arg)")
      }
    case .greaterThan(let arg):
      HStack {
        Text(.localizable(.asn))
        Image(systemName: "lessthan.circle")
        Text("\(arg)")
      }
    case .lessThan(let arg):
      HStack {
        Text(.localizable(.asn))
        Image(systemName: "greaterthan.circle")
        Text("\(arg)")
      }
    }
  }
}

#Preview {

  @Previewable @State var query = FilterState.AsnFilter.any

  AsnFilterView(query: $query)

}

#Preview("ASN Display view") {
  VStack {
    AsnFilterDisplayView(query: .any)
    AsnFilterDisplayView(query: .isNull)
    AsnFilterDisplayView(query: .isNotNull)
    AsnFilterDisplayView(query: .equalTo(42))
    AsnFilterDisplayView(query: .lessThan(42))
    AsnFilterDisplayView(query: .greaterThan(42))
  }
}
