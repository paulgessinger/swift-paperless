import Foundation
import Testing

@testable import DataModel

@Suite("FilterState local dates")
struct FilterStateLocalDatesTests {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
  }()

  private static func date(
    _ year: Int, _ month: Int, _ day: Int, hour: Int = 0
  ) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
  }

  /// A Wednesday.
  private static let now = date(2026, 8, 19, hour: 15)

  private func interval(_ range: FilterState.DateFilter.Range) -> (start: Date?, end: Date?) {
    range.interval(now: Self.now, calendar: Self.calendar)
  }

  @Test("no filter resolves to no interval")
  func any() {
    #expect(
      FilterState.DateFilter.Argument.any.interval(now: Self.now, calendar: Self.calendar) == nil)
  }

  @Test("between covers both of its days in full")
  func between() throws {
    let argument = FilterState.DateFilter.Argument.between(
      start: Self.date(2026, 3, 5, hour: 9), end: Self.date(2026, 3, 7, hour: 9))
    let interval = try #require(argument.interval(now: Self.now, calendar: Self.calendar))
    #expect(interval.start == Self.date(2026, 3, 5))
    #expect(interval.end == Self.date(2026, 3, 8))
  }

  @Test("an open bound stays open")
  func openBounds() throws {
    let from = try #require(
      FilterState.DateFilter.Argument.between(start: Self.date(2026, 3, 5), end: nil)
        .interval(now: Self.now, calendar: Self.calendar))
    #expect(from.start == Self.date(2026, 3, 5))
    #expect(from.end == nil)

    let until = try #require(
      FilterState.DateFilter.Argument.between(start: nil, end: Self.date(2026, 3, 5))
        .interval(now: Self.now, calendar: Self.calendar))
    #expect(until.start == nil)
    #expect(until.end == Self.date(2026, 3, 6))
  }

  @Test("the last N weeks, months and years reach back from now, whatever the count's sign")
  func within() {
    #expect(interval(.within(num: -1, interval: .week)).start == Self.date(2026, 8, 12, hour: 15))
    #expect(interval(.within(num: -3, interval: .month)).start == Self.date(2026, 5, 19, hour: 15))
    #expect(interval(.within(num: 3, interval: .month)).start == Self.date(2026, 5, 19, hour: 15))
    #expect(interval(.within(num: -2, interval: .year)).start == Self.date(2024, 8, 19, hour: 15))
    #expect(interval(.within(num: -1, interval: .week)).end == nil)
  }

  @Test("calendar ranges")
  func calendarRanges() {
    #expect(interval(.today).start == Self.date(2026, 8, 19))
    #expect(interval(.today).end == Self.date(2026, 8, 20))
    #expect(interval(.yesterday).start == Self.date(2026, 8, 18))
    #expect(interval(.yesterday).end == Self.date(2026, 8, 19))
    #expect(interval(.currentMonth).start == Self.date(2026, 8, 1))
    #expect(interval(.currentMonth).end == Self.date(2026, 9, 1))
    #expect(interval(.currentYear).start == Self.date(2026, 1, 1))
    #expect(interval(.currentYear).end == Self.date(2027, 1, 1))
    // Monday to Monday.
    #expect(interval(.previousWeek).start == Self.date(2026, 8, 10))
    #expect(interval(.previousWeek).end == Self.date(2026, 8, 17))
    #expect(interval(.previousMonth).start == Self.date(2026, 7, 1))
    #expect(interval(.previousMonth).end == Self.date(2026, 8, 1))
    #expect(interval(.previousQuarter).start == Self.date(2026, 4, 1))
    #expect(interval(.previousQuarter).end == Self.date(2026, 7, 1))
    #expect(interval(.previousYear).start == Self.date(2025, 1, 1))
    #expect(interval(.previousYear).end == Self.date(2026, 1, 1))
  }

  @Test("the previous quarter of a first quarter is the year before's last")
  func previousQuarterAcrossYears() {
    let range = FilterState.DateFilter.Range.previousQuarter.interval(
      now: Self.date(2026, 2, 10), calendar: Self.calendar)
    #expect(range.start == Self.date(2025, 10, 1))
    #expect(range.end == Self.date(2026, 1, 1))
  }
}
