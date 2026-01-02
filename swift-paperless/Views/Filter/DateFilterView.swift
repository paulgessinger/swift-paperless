//
//  AsnFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 02.01.26.
//

import DataModel
import SwiftUI

extension FilterState.DateFilter.Range {
  var localizedLabel: String {
    switch self {
    case .currentYear: String(localized: .localizable(.dateFilterCurrentYear))
    case .currentMonth: String(localized: .localizable(.dateFilterCurrentMonth))
    case .today: String(localized: .localizable(.dateFilterToday))
    case .yesterday: String(localized: .localizable(.dateFilterYesterday))
    case .previousWeek: String(localized: .localizable(.dateFilterPreviousWeek))
    case .previousMonth: String(localized: .localizable(.dateFilterPreviousMonth))
    case .previousQuarter: String(localized: .localizable(.dateFilterPreviousQuarter))
    case .previousYear: String(localized: .localizable(.dateFilterPreviousYear))

    case .within(let num, let interval):
      switch interval {
      case .week: String(localized: .localizable(.dateFilterWithinWeeks(num.magnitude)))
      case .month: String(localized: .localizable(.dateFilterWithinMonths(num.magnitude)))
      case .year: String(localized: .localizable(.dateFilterWithinYears(num.magnitude)))
      }
    }
  }
}

private struct ClearableDatePickerView: View {
  @Binding private var value: Date?

  init(value: Binding<Date?>) {
    _value = value
  }

  var body: some View {
    HStack {
      if let unwrapped = Binding(unwrapping: $value) {
        DatePicker(selection: unwrapped, displayedComponents: .date) {
          Image(systemName: "xmark.circle.fill")
            .foregroundColor(.secondary)
            .accessibilityLabel(String(localized: .localizable(.dateFilterDateClear)))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onTapGesture {
              value = nil
            }
        }
      } else {
        HStack {
          Image(systemName: "plus.circle.fill")
          Text(.localizable(.dateFilterDateAdd))
        }
        .foregroundColor(.accentColor)
        .onTapGesture {
          value = .now
        }
      }
    }
    .animation(.spring, value: value)
  }
}

private struct DateFilterModeView: View {
  typealias Argument = FilterState.DateFilter.Argument
  typealias Range = FilterState.DateFilter.Range

  @Binding var value: Argument

  @State private var modeValue: Argument

  init(value: Binding<Argument>) {
    _value = value
    self._modeValue = State(initialValue: value.wrappedValue)
  }

  private let rangeValues: [Range] = [
    .within(num: -1, interval: .week),
    .within(num: -1, interval: .month),
    .within(num: -3, interval: .month),
    .within(num: -1, interval: .year),
    .currentYear,
    .currentMonth,
    .today,
    .yesterday,
    .previousWeek,
    .previousMonth,
    .previousQuarter,
    .previousYear,
  ]

  var body: some View {
    Group {
      Picker(.localizable(.dateFilterRange), selection: $modeValue) {
        Text(.localizable(.none))
          .tag(Argument.any)
        Text(.localizable(.dateFilterBetween))
          .tag(Argument.between(start: nil, end: nil))

        Divider()

        Section(.localizable(.dateFilterRange)) {
          ForEach(rangeValues, id: \.self) { value in
            Text(value.localizedLabel)
              .tag(Argument.range(value))
          }
        }

      }

      if let btw = $value.between {
        LabeledContent {
          ClearableDatePickerView(value: btw.start)
        } label: {
          Text(.localizable(.dateFilterFromLabel))
            .padding(.vertical, 7)
        }

        LabeledContent {
          ClearableDatePickerView(value: btw.end)
        } label: {
          Text(.localizable(.dateFilterToLabel))
            .padding(.vertical, 7)
        }
      }
    }

    .onChange(of: modeValue) {
      value = modeValue
    }

    .onChange(of: value) {
      switch value {
      case .between:
        modeValue = .between(start: nil, end: nil)
      default:
        modeValue = value
        break
      }
    }
  }
}

struct DateFilterView: View {
  @Binding var queryOut: FilterState.DateFilter
  @State private var query: FilterState.DateFilter

  @Environment(\.dismiss) private var dismiss

  init(query: Binding<FilterState.DateFilter>) {
    _queryOut = query
    _query = State(initialValue: query.wrappedValue)
  }

  private func confirm() {
    Task {

      if case .between(start: nil, end: nil) = query.created {
        query.created = .any
      }

      if case .between(start: nil, end: nil) = query.added {
        query.added = .any
      }

      queryOut = query
      guard (try? await Task.sleep(for: .seconds(0.1))) != nil else {
        return
      }
      dismiss()
    }
  }

  private func clear() {
    queryOut = .init()
    query = .init()
  }

  var body: some View {
    NavigationStack {
      Form {
        Section(.localizable(.dateFilterCreated)) {
          DateFilterModeView(value: $query.created)
        }

        Section(.localizable(.dateFilterAdded)) {
          DateFilterModeView(value: $query.added)
        }

        if query.isActive {
          Section {
            Button(action: clear) {
              Label(localized: .localizable(.clearFilters), systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity, alignment: .center)
            }
          }
        }
      }

      .animation(.spring, value: query)

      .toolbar {
        SaveButton(action: confirm)
          .backport.glassProminentButtonStyle(or: .automatic)
      }

      .navigationTitle(.localizable(.dateFilterTitle))
      .navigationBarTitleDisplayMode(.inline)

    }
  }
}

struct DateFilterDisplayView: View {
  let query: FilterState.DateFilter

  var body: some View {
    HStack {
      if query.isActive {
        Image(systemName: "clock")
      }
      Text(.localizable(.dateFilterTitle))
    }
  }
}

#Preview {

  @Previewable @State var query = FilterState.DateFilter()

  DateFilterView(query: $query)

}
