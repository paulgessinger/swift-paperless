//
//  AsnFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 02.01.26.
//

import DataModel
import SwiftUI

extension FilterState.DateFilter.Range {
  public var localizedLabel: String {
    switch self {
    case .currentYear: String(localized: .app(.dateFilterCurrentYear))
    case .currentMonth: String(localized: .app(.dateFilterCurrentMonth))
    case .today: String(localized: .app(.dateFilterToday))
    case .yesterday: String(localized: .app(.dateFilterYesterday))
    case .previousWeek: String(localized: .app(.dateFilterPreviousWeek))
    case .previousMonth: String(localized: .app(.dateFilterPreviousMonth))
    case .previousQuarter: String(localized: .app(.dateFilterPreviousQuarter))
    case .previousYear: String(localized: .app(.dateFilterPreviousYear))

    case .within(let num, let interval):
      switch interval {
      case .week: String(localized: .app(.dateFilterWithinWeeks(num.magnitude)))
      case .month: String(localized: .app(.dateFilterWithinMonths(num.magnitude)))
      case .year: String(localized: .app(.dateFilterWithinYears(num.magnitude)))
      }
    }
  }
}

private struct DateFilterModeView: View {
  public typealias Argument = FilterState.DateFilter.Argument
  public typealias Range = FilterState.DateFilter.Range

  @Binding public var value: Argument

  @State private var modeValue: Argument
  @State private var rangeValues: [Range] = []
  @EnvironmentObject private var store: DocumentStore

  public init(value: Binding<Argument>) {
    _value = value
    self._modeValue = State(initialValue: value.wrappedValue)
  }

  public var body: some View {
    Group {
      Picker(.app(.dateFilterRange), selection: $modeValue) {
        Text(.app(.none))
          .tag(Argument.any)
        Text(.app(.dateFilterBetween))
          .tag(Argument.between(start: nil, end: nil))

        Divider()

        Section(.app(.dateFilterRange)) {
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
          Text(.app(.dateFilterFromLabel))
            .padding(.vertical, 7)
        }

        LabeledContent {
          ClearableDatePickerView(value: btw.end)
        } label: {
          Text(.app(.dateFilterToLabel))
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

    .task {
      var rangeValues: [Range] = [
        .within(num: -1, interval: .week),
        .within(num: -1, interval: .month),
        .within(num: -3, interval: .month),
        .within(num: -1, interval: .year),
        .currentYear,
        .currentMonth,
        .today,
        .yesterday,
      ]

      if store.repository.supports(feature: .dateFilterPreviousIntervals) {
        rangeValues += [
          .previousWeek,
          .previousMonth,
          .previousQuarter,
          .previousYear,
        ]
      }

      self.rangeValues = rangeValues
    }
  }
}

public struct DateFilterView: View {
  @Binding public var queryOut: FilterState.DateFilter
  @State private var query: FilterState.DateFilter

  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject private var store: DocumentStore

  public init(query: Binding<FilterState.DateFilter>) {
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

  public var body: some View {
    NavigationStack {
      Form {
        Section(.app(.dateFilterCreated)) {
          DateFilterModeView(value: $query.created)
        }

        Section(.app(.dateFilterAdded)) {
          DateFilterModeView(value: $query.added)
        }

        if store.repository.supports(feature: .dateFilterModified) {
          Section(.app(.dateFilterModified)) {
            DateFilterModeView(value: $query.modified)
          }
        }

        if query.isActive {
          Section {
            Button(action: clear) {
              Label(localized: .app(.clearFilters), systemImage: "arrow.counterclockwise")
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

      .navigationTitle(.app(.dateFilterTitle))
      .navigationBarTitleDisplayMode(.inline)

    }
  }
}

public struct DateFilterDisplayView: View {
  public let query: FilterState.DateFilter

  public init(query: FilterState.DateFilter) {
    self.query = query
  }

  public var body: some View {
    HStack {
      if query.isActive {
        Image(systemName: "clock")
      }
      Text(.app(.dateFilterTitle))
    }
  }
}

#Preview {

  @Previewable @State var query = FilterState.DateFilter()

  DateFilterView(query: $query)

}
