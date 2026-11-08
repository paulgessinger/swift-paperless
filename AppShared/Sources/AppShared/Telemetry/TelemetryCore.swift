//
//  TelemetryCore.swift
//  AppShared
//
//  Pure telemetry logic: coarsening, bucketing, the UTC-day gate and payload
//  assembly. Everything is computed from explicit inputs; nothing here reads
//  the bundle, the device or the defaults.
//

import Common
import Foundation

// MARK: - Values

public enum TelemetryValues {
  /// `major.minor`, never the patch level.
  public static func osVersion(major: Int, minor: Int) -> String {
    "\(major).\(minor)"
  }

  /// `major.minor.patch`, or `other` for anything that is not exactly three
  /// numeric components, so build tags and fork suffixes are never sent.
  public static func backendVersion(_ raw: String) -> String {
    guard let version = Version(raw)?.description, matches(version, #"^\d{1,4}\.\d{1,4}\.\d{1,4}$"#)
    else { return "other" }
    return version
  }

  /// The marketing version as is, or `0.0` if it isn't `major.minor[.patch]`.
  public static func appVersion(_ raw: String) -> String {
    matches(raw, #"^\d{1,4}(\.\d{1,4}){1,2}$"#) ? raw : "0.0"
  }

  /// The language code alone: `pt-BR` → `pt`, `zh-Hans` → `zh`. `und` when
  /// there is no two- or three-letter code.
  public static func language(_ identifier: String) -> String {
    let code = Locale(identifier: identifier).language.languageCode?.identifier.lowercased()
    guard let code, matches(code, "^[a-z]{2,3}$") else { return "und" }
    return code
  }

  private static func matches(_ value: String, _ pattern: String) -> Bool {
    value.range(of: pattern, options: .regularExpression) != nil
  }
}

// MARK: - UTC days

public enum TelemetryDay {
  private static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  /// The UTC day of `date` as `yyyy-MM-dd`.
  public static func string(for date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
  }

  /// The start of a `yyyy-MM-dd` UTC day, or `nil` if it doesn't parse.
  public static func date(for string: String) -> Date? {
    let parts = string.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }

  /// Whole UTC days from `from` to `to`.
  public static func days(from: Date, to: Date) -> Int {
    calendar.dateComponents(
      [.day], from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to)
    ).day ?? 0
  }

  /// The daily gate: at most one ping per category per UTC day.
  public static func shouldSend(lastSent: String?, now: Date) -> Bool {
    lastSent != string(for: now)
  }
}

// MARK: - Activity signals

/// The local install stamp written at opt-in.
public enum TelemetryInstallStamp: Equatable, Sendable {
  /// Opted in during first-run onboarding: the UTC day of the install.
  case day(String)
  /// Opted in with the app already set up. Always reports `existing`.
  case existing

  public init?(storedValue: String) {
    if storedValue == "existing" {
      self = .existing
    } else if TelemetryDay.date(for: storedValue) != nil {
      self = .day(storedValue)
    } else {
      return nil
    }
  }

  public var storedValue: String {
    switch self {
    case .day(let day): day
    case .existing: "existing"
    }
  }

  public func bucket(now: Date) -> TelemetryInstallAgeBucket {
    guard case .day(let day) = self, let date = TelemetryDay.date(for: day) else {
      return .existing
    }
    switch TelemetryDay.days(from: date, to: now) {
    case ..<7: return .underWeek
    case ..<30: return .underMonth
    case ..<365: return .underYear
    default: return .overYear
    }
  }
}

public enum TelemetryActiveDays {
  public static let window = 30

  /// `days` with today's UTC day added and anything outside the last 30 days
  /// (today included) removed.
  public static func recording(_ days: Set<String>, now: Date) -> Set<String> {
    var result = pruned(days, now: now)
    result.insert(TelemetryDay.string(for: now))
    return result
  }

  public static func pruned(_ days: Set<String>, now: Date) -> Set<String> {
    days.filter { day in
      guard let date = TelemetryDay.date(for: day) else { return false }
      let age = TelemetryDay.days(from: date, to: now)
      return age >= 0 && age < window
    }
  }

  public static func bucket(_ days: Set<String>, now: Date) -> TelemetryActiveDaysBucket? {
    TelemetryActiveDaysBucket(count: pruned(days, now: now).count)
  }
}

// MARK: - Assembly

/// The environment a health ping describes, gathered by `TelemetryService`.
public struct TelemetryEnvironment: Equatable, Sendable {
  public var channel: TelemetryChannel
  /// `CFBundleShortVersionString`.
  public var appVersion: String
  public var osMajor: Int
  public var osMinor: Int
  public var device: TelemetryDevice
  /// The localization the app runs in, such as `de` or `pt-BR`.
  public var localization: String
  /// The active server's version string as reported.
  public var backendVersion: String?
  public var apiVersion: UInt?
  public var documentCount: UInt?
  public var auth: ConnectionAuthMethod?
  public var clientCertificate: Bool
  public var customHeaders: Bool
  public var serverCount: Int
  public var availableFeatures: [TelemetryFeature]

  public init(
    channel: TelemetryChannel, appVersion: String, osMajor: Int, osMinor: Int,
    device: TelemetryDevice, localization: String, backendVersion: String? = nil,
    apiVersion: UInt? = nil, documentCount: UInt? = nil, auth: ConnectionAuthMethod? = nil,
    clientCertificate: Bool = false, customHeaders: Bool = false, serverCount: Int,
    availableFeatures: [TelemetryFeature] = TelemetryFeature.allCases
  ) {
    self.channel = channel
    self.appVersion = appVersion
    self.osMajor = osMajor
    self.osMinor = osMinor
    self.device = device
    self.localization = localization
    self.backendVersion = backendVersion
    self.apiVersion = apiVersion
    self.documentCount = documentCount
    self.auth = auth
    self.clientCertificate = clientCertificate
    self.customHeaders = customHeaders
    self.serverCount = serverCount
    self.availableFeatures = availableFeatures
  }
}

/// The local bookkeeping. Exists only while opted in.
public struct TelemetryState: Equatable, Sendable {
  public var healthLastSent: String?
  /// The UTC day the last successful feature ping reported.
  public var featureLastReported: String?
  /// Feature uses by the UTC day they were recorded on.
  public var pendingFeatures: [String: [TelemetryFeature: Int]] = [:]
  /// Setup errors by the UTC day they were hit on.
  public var pendingErrors: [String: Set<TelemetryError>] = [:]
  public var activeDays: Set<String> = []
  public var installStamp: TelemetryInstallStamp?

  public init(
    healthLastSent: String? = nil, featureLastReported: String? = nil,
    pendingFeatures: [String: [TelemetryFeature: Int]] = [:],
    pendingErrors: [String: Set<TelemetryError>] = [:],
    activeDays: Set<String> = [], installStamp: TelemetryInstallStamp? = nil
  ) {
    self.healthLastSent = healthLastSent
    self.featureLastReported = featureLastReported
    self.pendingFeatures = pendingFeatures
    self.pendingErrors = pendingErrors
    self.activeDays = activeDays
    self.installStamp = installStamp
  }

  /// Drops pending entries outside the last 30 UTC days.
  public mutating func prunePending(now: Date) {
    let kept = TelemetryActiveDays.pruned(
      Set(pendingFeatures.keys).union(pendingErrors.keys), now: now)
    pendingFeatures = pendingFeatures.filter { kept.contains($0.key) }
    pendingErrors = pendingErrors.filter { kept.contains($0.key) }
  }

  /// The day the next feature ping reports: the latest completed UTC day in
  /// the last 30 that was active or has pending data and is later than the
  /// last reported day. Older unreported days are never reported, so each
  /// activation sends at most one feature ping.
  public func featureReportDay(now: Date) -> String? {
    let today = TelemetryDay.string(for: now)
    let candidates = activeDays.union(pendingFeatures.keys).union(pendingErrors.keys)
    // `yyyy-MM-dd` strings order like the days they name.
    return TelemetryActiveDays.pruned(candidates, now: now)
      .filter { day in day < today && featureLastReported.map { day > $0 } ?? true }
      .max()
  }

  /// Marks `day` reported and drops the pending entries for it and earlier.
  public mutating func didReport(day: String) {
    featureLastReported = day
    pendingFeatures = pendingFeatures.filter { $0.key > day }
    pendingErrors = pendingErrors.filter { $0.key > day }
  }
}

public enum TelemetryPings {
  public static func healthPing(
    environment env: TelemetryEnvironment, state: TelemetryState, now: Date
  ) -> HealthPing {
    HealthPing(
      channel: env.channel,
      app: TelemetryValues.appVersion(env.appVersion),
      ios: TelemetryValues.osVersion(major: env.osMajor, minor: env.osMinor),
      device: env.device,
      lang: TelemetryValues.language(env.localization),
      backend: env.backendVersion.map(TelemetryValues.backendVersion),
      api: env.apiVersion.flatMap { $0 > 0 ? $0 : nil },
      docs: env.documentCount.map(TelemetryDocsBucket.init(count:)),
      auth: env.auth,
      client_cert: env.clientCertificate,
      custom_headers: env.customHeaders,
      servers: TelemetryServersBucket(count: env.serverCount),
      // Sending a ping means today is an active day.
      active_days_30: TelemetryActiveDays.bucket(
        TelemetryActiveDays.recording(state.activeDays, now: now), now: now) ?? .one,
      // No stamp means the user opted in without this process seeing it.
      install_age: state.installStamp?.bucket(now: now) ?? .existing)
  }

  /// The feature ping for `day`, with that day's uses and errors.
  public static func featurePing(
    environment env: TelemetryEnvironment, state: TelemetryState, day: String
  ) -> FeaturePing {
    let errors = TelemetryError.allCases.filter { state.pendingErrors[day]?.contains($0) == true }
    return FeaturePing(
      channel: env.channel,
      day: day,
      features: (state.pendingFeatures[day] ?? [:])
        .compactMapValues(TelemetryCountBucket.init(count:)),
      available: TelemetryFeature.allCases.filter(env.availableFeatures.contains),
      errors: errors.isEmpty ? nil : errors)
  }

  /// The exact bytes of one ping, or `nil` for a feature ping with no day to
  /// report. The service sends this with `pretty: false`; "What's sent" shows
  /// it with `pretty: true`.
  public static func encodedPing(
    _ endpoint: TelemetryEndpoint, environment: TelemetryEnvironment, state: TelemetryState,
    now: Date, pretty: Bool = false
  ) throws -> Data? {
    switch endpoint {
    case .health:
      return try TelemetryEncoding.encode(
        healthPing(environment: environment, state: state, now: now), pretty: pretty)
    case .feature:
      guard let day = state.featureReportDay(now: now) else { return nil }
      return try TelemetryEncoding.encode(
        featurePing(environment: environment, state: state, day: day), pretty: pretty)
    }
  }
}
