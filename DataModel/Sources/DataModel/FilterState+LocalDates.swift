//
//  FilterState+LocalDates.swift
//  DataModel
//
//  Resolves a date filter to concrete instants, for answering a filter on the
//  device. The server resolves the same arguments itself, so nothing else
//  needs this.
//

import Foundation

extension FilterState.DateFilter.Argument {
  /// The instants this argument selects, as a half-open interval: from
  /// `start` up to but not including `end`. `nil` for ``any``; a `nil` bound
  /// is open.
  ///
  /// Whole days in `calendar`'s time zone: a ``between(start:end:)`` covers
  /// both of its days, as the filter's own bounds are inclusive. The server
  /// decides in its time zone, so a document dated around midnight can land
  /// on the other side.
  public func interval(
    now: Date, calendar: Calendar
  ) -> (start: Date?, end: Date?)? {
    switch self {
    case .any:
      return nil
    case .between(let start, let end):
      return (
        start.map { calendar.startOfDay(for: $0) },
        end.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) }
      )
    case .range(let range):
      return range.interval(now: now, calendar: calendar)
    }
  }
}

extension FilterState.DateFilter.Range {
  /// See ``FilterState/DateFilter/Argument/interval(now:calendar:)``.
  public func interval(now: Date, calendar: Calendar) -> (start: Date?, end: Date?) {
    let today = calendar.startOfDay(for: now)
    func start(of component: Calendar.Component) -> Date {
      calendar.dateInterval(of: component, for: now)?.start ?? today
    }
    func shifted(_ date: Date, _ component: Calendar.Component, _ value: Int) -> Date {
      calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    switch self {
    case .within(let num, let interval):
      // Stored as the server spells it, "[-3 month to now]": the count is
      // negative. Either sign means "the last N".
      let component: Calendar.Component =
        switch interval {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
      return (shifted(now, component, -abs(num)), nil)
    case .currentYear:
      return (start(of: .year), shifted(start(of: .year), .year, 1))
    case .currentMonth:
      return (start(of: .month), shifted(start(of: .month), .month, 1))
    case .today:
      return (today, shifted(today, .day, 1))
    case .yesterday:
      return (shifted(today, .day, -1), today)
    case .previousWeek:
      return (shifted(start(of: .weekOfYear), .weekOfYear, -1), start(of: .weekOfYear))
    case .previousMonth:
      return (shifted(start(of: .month), .month, -1), start(of: .month))
    case .previousQuarter:
      return (shifted(start(of: .quarter), .month, -3), start(of: .quarter))
    case .previousYear:
      return (shifted(start(of: .year), .year, -1), start(of: .year))
    }
  }
}
