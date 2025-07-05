//
//  Helpers.swift
//  DataModel
//
//  Created by Paul Gessinger on 02.01.25.
//

import Foundation

func testData(_ file: String) -> Data? {
  guard let rel = URL(string: file) else {
    return nil
  }
  guard
    let url = Bundle.module.url(
      forResource: rel.deletingPathExtension().absoluteString,
      withExtension: ".\(rel.pathExtension)")
  else {
    return nil
  }

  do {
    return try Data(contentsOf: url)
  } catch {
    return nil
  }
}

func dateApprox(_ lhs: Date, _ rhs: Date) -> Bool {
  let distance = lhs.distance(to: rhs)
  return abs(distance) < 1
}

func datetime(
  year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0, second: Double = 0,
  tz: TimeZone = .current
) -> Date {
  var dateComponents = DateComponents()
  dateComponents.year = year
  dateComponents.month = month
  dateComponents.day = day
  dateComponents.timeZone = tz
  dateComponents.hour = hour
  dateComponents.minute = minute

  let fullSeconds = Int(second)
  let nanoseconds = Int((second - Double(fullSeconds)) * 1_000_000_000)
  dateComponents.second = fullSeconds
  dateComponents.nanosecond = nanoseconds

  var cal = Calendar.current
  cal.timeZone = tz
  let date = cal.date(from: dateComponents)!
  return date
}
