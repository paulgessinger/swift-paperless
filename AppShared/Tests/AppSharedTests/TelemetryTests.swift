import Common
import DataModel
import Foundation
import Networking
import Testing

@testable import AppShared

func utc(_ day: String, hour: Int = 12) -> Date {
  TelemetryDay.date(for: day)!.addingTimeInterval(TimeInterval(hour * 3600))
}

private func environment(
  backend: String? = "2.14.3", documents: UInt? = 1500
) -> TelemetryEnvironment {
  TelemetryEnvironment(
    channel: .dev, appVersion: "1.11.0", osMajor: 18, osMinor: 3, device: .iPhone,
    localization: "pt-BR", backendVersion: backend, apiVersion: 9, documentCount: documents,
    clientCertificate: false, customHeaders: true, serverCount: 1)
}

@Suite
struct TelemetryValuesTests {
  @Test("iOS versions are major.minor")
  func osVersion() {
    #expect(TelemetryValues.osVersion(major: 18, minor: 3) == "18.3")
    #expect(TelemetryValues.osVersion(major: 26, minor: 0) == "26.0")
  }

  @Test(
    "Backend versions are major.minor.patch, anything else is other",
    arguments: [
      ("2.14.3", "2.14.3"),
      ("v2.14.3", "2.14.3"),
      ("2.14.3-dev+abc123", "other"),
      ("2.14", "other"),
      ("2.14.3.1", "other"),
      ("nightly", "other"),
      ("", "other"),
    ])
  func backendVersion(raw: String, expected: String) {
    #expect(TelemetryValues.backendVersion(raw) == expected)
  }

  @Test("App versions that aren't major.minor[.patch] are not sent verbatim")
  func appVersion() {
    #expect(TelemetryValues.appVersion("1.11.0") == "1.11.0")
    #expect(TelemetryValues.appVersion("1.11") == "1.11")
    #expect(TelemetryValues.appVersion("1.11.0-beta") == "0.0")
  }

  @Test("Languages drop region and script")
  func language() {
    #expect(TelemetryValues.language("") == "und")
    #expect(TelemetryValues.language("en") == "en")
    #expect(TelemetryValues.language("pt-BR") == "pt")
    #expect(TelemetryValues.language("zh-Hans") == "zh")
    #expect(TelemetryValues.language("de_CH") == "de")
  }
}

@Suite
struct TelemetryBucketTests {
  @Test("Counts are 1, 2-9 or 10+, and zero has no bucket")
  func countBuckets() {
    #expect(TelemetryCountBucket(count: 0) == nil)
    #expect(TelemetryCountBucket(count: -1) == nil)
    #expect(TelemetryCountBucket(count: 1) == .one)
    #expect(TelemetryCountBucket(count: 2) == .few)
    #expect(TelemetryCountBucket(count: 9) == .few)
    #expect(TelemetryCountBucket(count: 10) == .many)
    #expect(TelemetryCountBucket(count: 5000) == .many)
  }

  @Test("Document counts and server counts")
  func docsAndServers() {
    #expect(TelemetryDocsBucket(count: 0) == .under1k)
    #expect(TelemetryDocsBucket(count: 999) == .under1k)
    #expect(TelemetryDocsBucket(count: 1000) == .under10k)
    #expect(TelemetryDocsBucket(count: 10000) == .atLeast10k)
    #expect(TelemetryServersBucket(count: 0) == .one)
    #expect(TelemetryServersBucket(count: 1) == .one)
    #expect(TelemetryServersBucket(count: 4) == .several)
  }

  @Test("Unused features are absent from the feature ping")
  func zeroIsAbsent() {
    let state = TelemetryState(pendingFeatures: ["2026-01-04": [.search: 0, .filter: 3]])
    let ping = TelemetryPings.featurePing(
      environment: environment(), state: state, day: "2026-01-04")
    #expect(ping.features == [.filter: .few])
  }
}

@Suite
struct TelemetryActivityTests {
  @Test("active_days_30 counts distinct UTC days in the last 30")
  func activeDays() {
    let now = utc("2026-03-31")
    var days: Set<String> = ["2026-03-01", "2026-03-02", "2026-02-28"]
    days = TelemetryActiveDays.recording(days, now: now)
    // 2026-03-01 is 30 days back and falls out; 2026-03-02 is the oldest kept.
    #expect(days == ["2026-03-02", "2026-03-31"])
    #expect(TelemetryActiveDays.bucket(days, now: now) == .upToWeek)

    #expect(TelemetryActiveDays.bucket([], now: now) == nil)
    #expect(TelemetryActiveDays.bucket(["2026-03-31"], now: now) == .one)

    let twenty = Set(
      (0..<20).map { TelemetryDay.string(for: now.addingTimeInterval(-86400 * Double($0))) })
    #expect(TelemetryActiveDays.bucket(twenty, now: now) == .upTo20)
    let all = Set(
      (0..<40).map { TelemetryDay.string(for: now.addingTimeInterval(-86400 * Double($0))) })
    #expect(TelemetryActiveDays.pruned(all, now: now).count == 30)
    #expect(TelemetryActiveDays.bucket(all, now: now) == .atLeast21)
  }

  @Test("Recording the same day twice counts once")
  func sameDay() {
    let days = TelemetryActiveDays.recording(
      TelemetryActiveDays.recording([], now: utc("2026-01-05", hour: 1)),
      now: utc("2026-01-05", hour: 23))
    #expect(days == ["2026-01-05"])
  }

  @Test("install_age buckets from the stamp, and existing stays existing")
  func installAge() {
    let stamp = TelemetryInstallStamp.day("2026-01-01")
    #expect(stamp.bucket(now: utc("2026-01-01")) == .underWeek)
    #expect(stamp.bucket(now: utc("2026-01-07")) == .underWeek)
    #expect(stamp.bucket(now: utc("2026-01-08")) == .underMonth)
    #expect(stamp.bucket(now: utc("2026-01-31")) == .underYear)
    #expect(stamp.bucket(now: utc("2027-01-01")) == .overYear)
    #expect(TelemetryInstallStamp.existing.bucket(now: utc("2026-01-01")) == .existing)

    #expect(TelemetryInstallStamp(storedValue: "existing") == .existing)
    #expect(TelemetryInstallStamp(storedValue: "2026-01-01") == .day("2026-01-01"))
    #expect(TelemetryInstallStamp(storedValue: "garbage") == nil)
  }

  @Test("The daily gate opens once per UTC day")
  func dailyGate() {
    #expect(TelemetryDay.shouldSend(lastSent: nil, now: utc("2026-01-05")))
    #expect(!TelemetryDay.shouldSend(lastSent: "2026-01-05", now: utc("2026-01-05", hour: 23)))
    #expect(TelemetryDay.shouldSend(lastSent: "2026-01-05", now: utc("2026-01-06", hour: 0)))
  }

  @Test("The feature ping reports the latest completed day not yet reported")
  func featureReportDay() {
    let now = utc("2026-01-10")
    // Today is never reported.
    #expect(TelemetryState(activeDays: ["2026-01-10"]).featureReportDay(now: now) == nil)
    #expect(
      TelemetryState(activeDays: ["2026-01-03", "2026-01-07", "2026-01-10"])
        .featureReportDay(now: now) == "2026-01-07")
    // Pending data alone makes a day reportable.
    #expect(
      TelemetryState(
        pendingFeatures: ["2026-01-08": [.search: 1]], activeDays: ["2026-01-07"]
      ).featureReportDay(now: now) == "2026-01-08")
    #expect(
      TelemetryState(pendingErrors: ["2026-01-09": [.tls]]).featureReportDay(now: now)
        == "2026-01-09")
    // Nothing at or before the last reported day.
    #expect(
      TelemetryState(featureLastReported: "2026-01-07", activeDays: ["2026-01-07"])
        .featureReportDay(now: now) == nil)
    // Nothing older than the 30-day window.
    #expect(
      TelemetryState(activeDays: ["2025-12-11", "2025-12-12"]).featureReportDay(now: now)
        == "2025-12-12")
    #expect(TelemetryState(activeDays: ["2025-12-11"]).featureReportDay(now: now) == nil)
  }

  @Test("Pruning drops the reported day and earlier ones, not later ones")
  func prunedReported() {
    let pending = TelemetryPending(
      features: [
        "2026-01-03": [.notes: 1], "2026-01-04": [.search: 2], "2026-01-05": [.filter: 1],
      ],
      errors: ["2026-01-04": [.tls], "2026-01-05": [.auth]]
    ).pruned(now: utc("2026-01-05"), lastReported: "2026-01-04")
    #expect(pending.features == ["2026-01-05": [.filter: 1]])
    #expect(pending.errors == ["2026-01-05": [.auth]])
  }

  @Test("Pending entries older than 30 days are pruned")
  func prunePending() {
    let pending = TelemetryPending(
      features: ["2025-12-11": [.notes: 1], "2025-12-12": [.search: 1]],
      errors: ["2025-12-01": [.tls], "2026-01-10": [.auth]]
    ).pruned(now: utc("2026-01-10"), lastReported: nil)
    #expect(pending.features == ["2025-12-12": [.search: 1]])
    #expect(pending.errors == ["2026-01-10": [.auth]])
  }

  @Test("Merging adds counts and unites errors per day")
  func mergePending() {
    let merged = TelemetryPending.merged([
      TelemetryPending(
        features: ["2026-01-04": [.search: 2, .notes: 1]], errors: ["2026-01-04": [.tls]]),
      TelemetryPending(
        features: ["2026-01-04": [.search: 1], "2026-01-05": [.filter: 1]],
        errors: ["2026-01-04": [.auth, .tls]]),
    ])
    #expect(
      merged.features == ["2026-01-04": [.search: 3, .notes: 1], "2026-01-05": [.filter: 1]])
    #expect(merged.errors == ["2026-01-04": [.tls, .auth]])
  }

  @Test("Months and ISO weeks are UTC, with ISO week-numbering years")
  func monthAndWeek() {
    #expect(TelemetryDay.month(for: utc("2026-01-05")) == "2026-01")
    #expect(TelemetryDay.month(for: utc("2026-12-31", hour: 23)) == "2026-12")
    // 2026-12-31 is a Thursday, so its week is the year's 53rd and holds
    // 2027-01-01 too; 2027-01-04 is the first Monday of 2027-W01.
    #expect(TelemetryDay.isoWeek(for: utc("2026-12-31")) == "2026-W53")
    #expect(TelemetryDay.isoWeek(for: utc("2027-01-01")) == "2026-W53")
    #expect(TelemetryDay.isoWeek(for: utc("2027-01-03", hour: 23)) == "2026-W53")
    #expect(TelemetryDay.isoWeek(for: utc("2027-01-04", hour: 0)) == "2027-W01")
    // 2025-12-29 is a Monday in 2026-W01.
    #expect(TelemetryDay.isoWeek(for: utc("2025-12-29")) == "2026-W01")
    // Sunday 2026-11-08 and Monday 2026-11-09.
    #expect(TelemetryDay.isoWeek(for: utc("2026-11-08", hour: 23)) == "2026-W45")
    #expect(TelemetryDay.isoWeek(for: utc("2026-11-09", hour: 0)) == "2026-W46")
  }

  @Test("UTC days don't follow the local time zone")
  func utcDay() {
    // 23:30 UTC is already the next day in most of Europe.
    let date = utc("2026-06-01").addingTimeInterval(11.5 * 3600)
    #expect(TelemetryDay.string(for: date) == "2026-06-01")
  }
}

@Suite
struct TelemetryPingsTests {
  @Test("The health ping carries only coarsened values")
  func healthPing() throws {
    let state = TelemetryState(
      pendingErrors: ["2026-01-05": [.timeout, .tls]], activeDays: ["2026-01-05"],
      installStamp: .existing)
    let ping = TelemetryPings.healthPing(
      environment: environment(backend: "2.14.3-dev"), state: state, now: utc("2026-01-05"))
    #expect(ping.ios == "18.3")
    #expect(ping.lang == "pt")
    #expect(ping.backend == "other")
    #expect(ping.docs == .under10k)
    #expect(ping.servers == .one)
    #expect(ping.active_days_30 == .one)
    #expect(ping.install_age == .existing)
    #expect(ping.first_month)
    #expect(ping.first_week)

    let data = try #require(
      try TelemetryPings.encodedPing(
        .health, environment: environment(),
        state: TelemetryState(pendingErrors: ["2026-01-05": [.tls]]), now: utc("2026-01-05")))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    // Errors go in the feature ping.
    #expect(json["errors"] == nil)
    // Without bookkeeping yet: today counts as active, the stamp as existing.
    #expect(json["active_days_30"] as? String == "1")
    #expect(json["install_age"] as? String == "existing")
    #expect(json["first_month"] as? Bool == true)
    #expect(json["first_week"] as? Bool == true)
    // A connection without a recorded sign-in method sends no `auth`.
    #expect(json["auth"] == nil)
    #expect(
      Set(json.keys).isSubset(of: [
        "channel", "app", "ios", "device", "lang", "backend", "api", "docs", "auth",
        "client_cert", "custom_headers", "servers", "active_days_30", "install_age",
        "first_month", "first_week",
      ]))
  }

  @Test("first_month and first_week are true until a health ping of that period was sent")
  func firstOfPeriod() {
    func ping(_ state: TelemetryState, _ day: String) -> (Bool, Bool) {
      let ping = TelemetryPings.healthPing(environment: environment(), state: state, now: utc(day))
      return (ping.first_month, ping.first_week)
    }
    // Wednesday 2026-11-04.
    let sent = TelemetryState(healthLastMonth: "2026-11", healthLastWeek: "2026-W45")
    #expect(ping(sent, "2026-11-08") == (false, false))
    #expect(ping(sent, "2026-11-09") == (false, true))
    #expect(ping(sent, "2026-12-01") == (true, true))
    #expect(ping(TelemetryState(), "2026-11-08") == (true, true))
  }

  @Test("The feature ping lists available features in schema order")
  func featurePing() throws {
    let state = TelemetryState(
      pendingFeatures: ["2026-01-04": [.notes: 12], "2026-01-05": [.search: 1]],
      pendingErrors: ["2026-01-04": [.timeout, .tls]])
    let ping = TelemetryPings.featurePing(
      environment: environment(), state: state, day: "2026-01-04")
    #expect(ping.day == "2026-01-04")
    #expect(ping.features == [.notes: .many])
    #expect(ping.available == TelemetryFeature.allCases)
    #expect(ping.errors == [.tls, .timeout])

    // Nothing to report on the first day.
    #expect(
      try TelemetryPings.encodedPing(
        .feature, environment: environment(), state: TelemetryState(activeDays: ["2026-01-05"]),
        now: utc("2026-01-05")) == nil)

    let data = try #require(
      try TelemetryPings.encodedPing(
        .feature, environment: environment(), state: TelemetryState(activeDays: ["2026-01-04"]),
        now: utc("2026-01-05")))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((json["features"] as? [String: Any])?.isEmpty == true)
    // Empty errors are left out rather than sent as null or [].
    #expect(Set(json.keys) == ["channel", "day", "features", "available"])
    #expect(json["day"] as? String == "2026-01-04")
  }

  @Test("Debug and simulator builds report as the dev channel")
  func channels() {
    #expect(TelemetryChannel(.Debug) == .dev)
    #expect(TelemetryChannel(.Simulator) == .dev)
    #expect(TelemetryChannel(.TestFlight) == .testflight)
    #expect(TelemetryChannel(.AppStore) == .appstore)
  }
}

@Suite
struct TelemetryClassificationTests {
  @Test("Request errors map onto the closed error set")
  func errors() {
    #expect(TelemetryError(classifying: RequestError.certificate(detail: "x")) == .tls)
    #expect(TelemetryError(classifying: RequestError.unauthorized(detail: "x")) == .auth)
    #expect(TelemetryError(classifying: RequestError.forbidden(detail: nil)) == .auth)
    #expect(
      TelemetryError(classifying: RequestError.unsupportedVersion(sentVersion: nil))
        == .backendTooOld)
    #expect(
      TelemetryError(
        classifying: RequestError.connectivity(
          code: .timedOut, kind: .serverNotResponding, detail: "")) == .timeout)
    #expect(
      TelemetryError(
        classifying: RequestError.connectivity(
          code: .cannotFindHost, kind: .hostNotFound, detail: "")) == .unreachable)
    #expect(
      TelemetryError(
        classifying: RequestError.connectivity(
          code: .notConnectedToInternet, kind: .offline, detail: "")) == nil)
    #expect(TelemetryError(classifying: URLError(.serverCertificateUntrusted)) == .tls)
    #expect(TelemetryError(classifying: URLError(.timedOut)) == .timeout)
    #expect(TelemetryError(classifying: CancellationError()) == nil)
  }

  @Test("Filter changes count as saved view, search or filter")
  func filterChanges() {
    let base = FilterState.empty
    var savedView = base
    savedView.savedView = 3
    savedView.tags = .any
    #expect(TelemetryFeature.filterChanges(from: base, to: savedView) == [.savedView])

    var search = base
    search.searchText = "inv"
    #expect(TelemetryFeature.filterChanges(from: base, to: search) == [.search])
    var refined = search
    refined.searchText = "invoice"
    #expect(TelemetryFeature.filterChanges(from: search, to: refined) == [])

    var filtered = base
    filtered.correspondent = .anyOf(ids: [4])
    #expect(TelemetryFeature.filterChanges(from: base, to: filtered) == [.filter])

    var sorted = base
    sorted.sorting = .init(field: .title, order: .ascending)
    #expect(TelemetryFeature.filterChanges(from: base, to: sorted) == [])
  }
}

// MARK: - Service

final class TelemetryTransportSpy: TelemetryTransport, @unchecked Sendable {
  private let lock = NSLock()
  private var _sent: [(TelemetryEndpoint, Data)] = []
  var failing = false

  var sent: [(TelemetryEndpoint, Data)] { lock.withLock { _sent } }

  func count(_ endpoint: TelemetryEndpoint) -> Int {
    sent.filter { $0.0 == endpoint }.count
  }

  func send(_ body: Data, to endpoint: TelemetryEndpoint) async throws {
    if lock.withLock({ failing }) { throw URLError(.cannotConnectToHost) }
    lock.withLock { _sent.append((endpoint, body)) }
  }
}

final class TelemetryTestClock: @unchecked Sendable {
  private let lock = NSLock()
  private var _now: Date
  init(_ now: Date) { _now = now }
  var now: Date {
    get { lock.withLock { _now } }
    set { lock.withLock { _now = newValue } }
  }
}

@MainActor
@Suite
struct TelemetryServiceTests {
  let defaults: UserDefaults
  let spy = TelemetryTransportSpy()
  let clock = TelemetryTestClock(utc("2026-01-05"))
  let consent = Consent()

  @MainActor
  final class Consent {
    var optedIn: Bool? = nil
  }

  init() {
    let suite = "telemetry-tests-\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
  }

  private func makeService() -> TelemetryService {
    makeService(.app) { [consent] in consent.optedIn == true }
  }

  private func makeService(
    _ process: TelemetryProcess, isConsented: @escaping @MainActor () -> Bool
  ) -> TelemetryService {
    TelemetryService(
      isConsented: isConsented,
      transport: spy,
      process: process,
      defaults: defaults,
      now: { [clock] in clock.now })
  }

  /// One process's settings: its own `.device` suite, and `defaults` as the
  /// app group every process shares.
  private func processSettings() -> SettingsStore {
    let device = UserDefaults(suiteName: "telemetry-tests-device-\(UUID().uuidString)")!
    return SettingsStore(suites: [.device: device, .shared: defaults])
  }

  /// A service consenting the way production does, through `settings`.
  private func makeService(
    _ process: TelemetryProcess, settings: SettingsStore
  ) -> TelemetryService {
    makeService(process) { settings[SettingKey<Bool?>.telemetryOptIn] == true }
  }

  private var storedKeys: [String] {
    TelemetryStorage(defaults: defaults, process: .app).storedKeys
  }

  /// The stored telemetry values, for checking which keys an operation wrote.
  private var storedValues: NSDictionary {
    NSDictionary(
      dictionary: Dictionary(
        uniqueKeysWithValues: storedKeys.map { ($0, defaults.object(forKey: $0)!) }))
  }

  private let extensionKey = TelemetryStorage.pendingKeyPrefix + "ShareExtension"

  private func activate(_ service: TelemetryService) async {
    service.appBecameActive { environment() }
    await service.waitForPendingSends()
  }

  @Test("Nothing is recorded, stored or sent before opt-in")
  func nothingBeforeOptIn() async {
    let service = makeService()
    service.record(.search)
    service.record(.tls)
    service.consentDidChange(hasConnection: true)
    await activate(service)

    #expect(spy.sent.isEmpty)
    #expect(storedKeys.isEmpty)

    consent.optedIn = false
    await activate(service)
    #expect(spy.sent.isEmpty)
    #expect(storedKeys.isEmpty)
  }

  private func featurePings() throws -> [FeaturePing] {
    try spy.sent.filter { $0.0 == .feature }.map {
      try JSONDecoder().decode(FeaturePing.self, from: $0.1)
    }
  }

  private var state: TelemetryState {
    TelemetryStorage(defaults: defaults, process: .app).load(now: clock.now)
  }

  @Test("Health goes out once per UTC day, feature once per completed day")
  func oncePerDay() async throws {
    let service = makeService()
    consent.optedIn = true
    service.consentDidChange(hasConnection: true)

    await activate(service)
    await activate(service)
    clock.now = utc("2026-01-05", hour: 23)
    await activate(service)
    #expect(spy.count(.health) == 1)
    // No completed day yet.
    #expect(spy.count(.feature) == 0)

    clock.now = utc("2026-01-06", hour: 0)
    await activate(service)
    await activate(service)
    #expect(spy.count(.health) == 2)
    #expect(try featurePings().map(\.day) == ["2026-01-05"])
  }

  private func healthPings() throws -> [HealthPing] {
    try spy.sent.filter { $0.0 == .health }.map {
      try JSONDecoder().decode(HealthPing.self, from: $0.1)
    }
  }

  @Test("Only the first successful health ping of a month or week is marked first")
  func firstOfPeriod() async throws {
    let service = makeService()
    consent.optedIn = true
    // Saturday 2026-10-31, Sunday 2026-11-01, Monday 2026-11-02.
    for day in ["2026-10-31", "2026-11-01", "2026-11-02", "2026-11-03"] {
      clock.now = utc(day)
      await activate(service)
    }
    #expect(try healthPings().map(\.first_month) == [true, true, false, false])
    #expect(try healthPings().map(\.first_week) == [true, false, true, false])
    #expect(state.healthLastMonth == "2026-11")
    #expect(state.healthLastWeek == "2026-W45")
  }

  @Test("A failed health send leaves the period markers, so the retry is still first")
  func failedSendKeepsPeriodMarkers() async throws {
    let service = makeService()
    consent.optedIn = true
    await activate(service)

    clock.now = utc("2026-02-02")
    spy.failing = true
    await activate(service)
    #expect(state.healthLastSent == "2026-01-05")
    #expect(state.healthLastMonth == "2026-01")
    #expect(state.healthLastWeek == "2026-W02")

    spy.failing = false
    clock.now = utc("2026-02-03")
    await activate(service)
    let last = try #require(try healthPings().last)
    #expect(last.first_month)
    #expect(last.first_week)
    #expect(state.healthLastMonth == "2026-02")
    #expect(state.healthLastWeek == "2026-W06")
  }

  @Test("A day without feature use still gets an empty feature ping")
  func emptyFeaturePing() async throws {
    let service = makeService()
    consent.optedIn = true
    await activate(service)
    clock.now = utc("2026-01-06")
    await activate(service)

    let ping = try #require(try featurePings().first)
    #expect(ping.day == "2026-01-05")
    #expect(ping.features.isEmpty)
    #expect(ping.errors == nil)
    #expect(ping.available == TelemetryFeature.allCases)
  }

  @Test("Uses and errors are reported under the day they were recorded on")
  func perDayAttribution() async throws {
    let service = makeService()
    consent.optedIn = true
    service.record(.search)
    service.record(.search)
    service.record(.scanStarted)
    service.record(.auth)
    await activate(service)

    clock.now = utc("2026-01-06", hour: 1)
    service.record(.notes)
    service.record(.timeout)
    await activate(service)

    let feature = try #require(try featurePings().first)
    #expect(feature.day == "2026-01-05")
    #expect(feature.features == [.search: .few, .scanStarted: .one])
    #expect(feature.errors == [.auth])

    let healthBody = try #require(spy.sent.last { $0.0 == .health }?.1)
    let health = try #require(
      try JSONSerialization.jsonObject(with: healthBody) as? [String: Any])
    #expect(health["errors"] == nil)
    #expect(health["install_age"] as? String == "existing")

    // Today's uses survive the send.
    #expect(state.featureLastReported == "2026-01-05")
    #expect(state.pendingFeatures == ["2026-01-06": [.notes: 1]])
    #expect(state.pendingErrors == ["2026-01-06": [.timeout]])
  }

  @Test("After a gap, only the latest unreported day is sent, under its own date")
  func gap() async throws {
    let service = makeService()
    consent.optedIn = true
    clock.now = utc("2026-01-03")
    service.record(.filter)
    await activate(service)

    clock.now = utc("2026-01-04")
    service.record(.search)
    spy.failing = true
    await activate(service)
    spy.failing = false

    clock.now = utc("2026-01-09")
    await activate(service)
    let pings = try featurePings()
    #expect(pings.map(\.day) == ["2026-01-04"])
    #expect(pings.first?.features == [.search: .one])
    // 2026-01-03 is dropped, not sent later.
    #expect(state.pendingFeatures.isEmpty)
    clock.now = utc("2026-01-09", hour: 20)
    await activate(service)
    #expect(spy.count(.feature) == 1)
  }

  @Test("Uses recorded on a day the app wasn't opened are reported")
  func shareExtensionOnlyDay() async throws {
    let appSettings = processSettings()
    let app = makeService(.app, settings: appSettings)
    appSettings[SettingKey<Bool?>.telemetryOptIn] = true
    await activate(app)
    clock.now = utc("2026-01-06")
    await activate(app)

    // The share extension records into the same defaults and never sends.
    clock.now = utc("2026-01-07")
    makeService(.shareExtension, settings: processSettings()).record(.documentShare)

    clock.now = utc("2026-01-08")
    await activate(app)
    #expect(try featurePings().map(\.day) == ["2026-01-05", "2026-01-07"])
    #expect(try featurePings().last?.features == [.documentShare: .one])
  }

  @Test("A failed send is dropped and tried on the next activation")
  func failedSend() async throws {
    let service = makeService()
    consent.optedIn = true
    service.record(.notes)
    await activate(service)

    clock.now = utc("2026-01-06")
    spy.failing = true
    await activate(service)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 0)
    #expect(state.pendingFeatures == ["2026-01-05": [.notes: 1]])
    #expect(state.featureLastReported == nil)

    spy.failing = false
    await activate(service)
    #expect(spy.count(.health) == 2)
    #expect(try featurePings().map(\.day) == ["2026-01-05"])
    #expect(try featurePings().first?.features == [.notes: .one])
  }

  @Test("Recording prunes pending entries older than 30 days")
  func pruning() {
    let service = makeService()
    consent.optedIn = true
    TelemetryStorage(defaults: defaults, process: .app).ownPending = TelemetryPending(
      features: ["2025-12-01": [.notes: 1]], errors: ["2025-12-01": [.tls]])
    service.record(.search)
    #expect(state.pendingFeatures == ["2026-01-05": [.search: 1]])
    #expect(state.pendingErrors.isEmpty)
  }

  @Test("Opting in during onboarding stamps the day, later opt-ins are existing")
  func installStamp() {
    let service = makeService()
    consent.optedIn = true
    service.consentDidChange(hasConnection: false)
    #expect(state.installStamp == .day("2026-01-05"))

    // A second change keeps the first stamp.
    service.consentDidChange(hasConnection: true)
    #expect(state.installStamp == .day("2026-01-05"))

    consent.optedIn = false
    service.consentDidChange(hasConnection: true)
    consent.optedIn = true
    service.consentDidChange(hasConnection: true)
    #expect(state.installStamp == .existing)
  }

  @Test("Opting out deletes all local state and stops sending")
  func optOut() async {
    let service = makeService()
    consent.optedIn = true
    service.consentDidChange(hasConnection: false)
    service.record(.filter)
    service.record(.timeout)
    await activate(service)
    #expect(!storedKeys.isEmpty)

    #expect(state.healthLastMonth == "2026-01")
    #expect(state.healthLastWeek == "2026-W02")

    consent.optedIn = false
    service.consentDidChange(hasConnection: true)
    #expect(storedKeys.isEmpty)
    #expect(state.healthLastMonth == nil)
    #expect(state.healthLastWeek == nil)

    clock.now = utc("2026-01-06")
    service.record(.filter)
    await activate(service)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 0)
    #expect(storedKeys.isEmpty)
  }

  @Test("A service starting without consent removes leftover state")
  func clearsLeftovers() {
    defaults.set(["2026-01-01"], forKey: TelemetryStorage.Key.activeDays.rawValue)
    _ = makeService()
    #expect(storedKeys.isEmpty)
  }

  // MARK: Several processes

  @Test("The share extension reads the opt-in the app wrote")
  func sharedConsent() {
    let app = processSettings()
    let shareExtension = processSettings()
    #expect(SettingKey<Bool?>.telemetryOptIn.scope == .shared)
    app[SettingKey<Bool?>.telemetryOptIn] = true
    #expect(shareExtension[SettingKey<Bool?>.telemetryOptIn] == true)

    makeService(.shareExtension, settings: shareExtension).record(.shareExtensionUploaded)
    #expect(state.pendingFeatures == ["2026-01-05": [.shareExtensionUploaded: 1]])
  }

  @Test("Each process writes only its own keys")
  func singleWriter() async throws {
    let appSettings = processSettings()
    appSettings[SettingKey<Bool?>.telemetryOptIn] = true
    let app = makeService(.app, settings: appSettings)
    let shareExtension = makeService(.shareExtension, settings: processSettings())
    app.consentDidChange(hasConnection: true)
    app.record(.search)
    shareExtension.record(.shareExtensionUploaded)
    await activate(app)
    #expect(spy.count(.health) == 1)

    // An extension record changes its pending key and nothing else, so it
    // can't roll back the app's send markers.
    var before = storedValues as! [String: Any]
    shareExtension.record(.shareExtensionUploaded)
    var after = storedValues as! [String: Any]
    before[extensionKey] = nil
    after[extensionKey] = nil
    #expect(NSDictionary(dictionary: before) == NSDictionary(dictionary: after))
    #expect(state.healthLastSent == "2026-01-05")

    // Nothing the app does writes the extension's key.
    let extensionPending = try #require(defaults.object(forKey: extensionKey) as? NSDictionary)
    app.record(.notes)
    app.record(.tls)
    clock.now = utc("2026-01-06")
    await activate(app)
    #expect(defaults.object(forKey: extensionKey) as? NSDictionary == extensionPending)

    let ping = try #require(try featurePings().first)
    #expect(ping.day == "2026-01-05")
    #expect(ping.features == [.search: .one, .notes: .one, .shareExtensionUploaded: .few])
    #expect(ping.errors == [.tls])
  }

  @Test("Reported days are skipped, and pruned by the extension's next record")
  func reportedExtensionDays() async throws {
    let appSettings = processSettings()
    appSettings[SettingKey<Bool?>.telemetryOptIn] = true
    let app = makeService(.app, settings: appSettings)
    let shareExtension = makeService(.shareExtension, settings: processSettings())
    shareExtension.record(.shareExtensionUploaded)
    await activate(app)

    clock.now = utc("2026-01-06")
    await activate(app)
    #expect(try featurePings().map(\.day) == ["2026-01-05"])
    // Still stored, but no longer counted.
    #expect(defaults.object(forKey: extensionKey) != nil)
    #expect(state.pendingFeatures.isEmpty)
    #expect(state.featureReportDay(now: clock.now) == nil)

    shareExtension.record(.shareExtensionUploaded)
    let stored = TelemetryStorage(defaults: defaults, process: .shareExtension).ownPending
    #expect(stored.features == ["2026-01-06": [.shareExtensionUploaded: 1]])

    clock.now = utc("2026-01-07")
    await activate(app)
    #expect(try featurePings().map(\.day) == ["2026-01-05", "2026-01-06"])
    #expect(try featurePings().last?.features == [.shareExtensionUploaded: .one])
  }

  @Test("Opting out in the app deletes every process's state")
  func optOutClearsAllProcesses() async {
    let appSettings = processSettings()
    appSettings[SettingKey<Bool?>.telemetryOptIn] = true
    let app = makeService(.app, settings: appSettings)
    let shareExtension = makeService(.shareExtension, settings: processSettings())
    app.consentDidChange(hasConnection: false)
    app.record(.search)
    shareExtension.record(.shareExtensionUploaded)
    await activate(app)
    #expect(storedKeys.contains(extensionKey))

    appSettings[SettingKey<Bool?>.telemetryOptIn] = false
    app.consentDidChange(hasConnection: true)
    #expect(storedKeys.isEmpty)

    shareExtension.record(.shareExtensionUploaded)
    #expect(storedKeys.isEmpty)
  }

  @Test("An extension never deletes or sends", arguments: [true, false])
  func extensionNeverClears(optedIn: Bool) async {
    let appSettings = processSettings()
    appSettings[SettingKey<Bool?>.telemetryOptIn] = true
    let app = makeService(.app, settings: appSettings)
    app.record(.search)
    await activate(app)
    let before = storedValues

    // Seen by the extension through the shared suite.
    appSettings[SettingKey<Bool?>.telemetryOptIn] = optedIn
    let shareExtension = makeService(.shareExtension, settings: processSettings())
    shareExtension.consentDidChange(hasConnection: true)
    clock.now = utc("2026-01-06")
    shareExtension.appBecameActive { environment() }
    await shareExtension.waitForPendingSends()

    #expect(storedValues == before)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 0)
  }

  @Test("The disclosure renders the payloads the service sends")
  func preview() async throws {
    let service = makeService()
    consent.optedIn = true
    service.record(.savedView)
    service.record(.tls)
    clock.now = utc("2026-01-06")
    service.appBecameActive { environment() }
    let preview = service.preview(environment: environment())
    await service.waitForPendingSends()

    // Nothing left to report until tomorrow.
    #expect(service.preview(environment: environment())[.feature] == nil)
    #expect(service.preview(environment: environment())[.health] != nil)

    for endpoint in TelemetryEndpoint.allCases {
      let shown =
        try JSONSerialization.jsonObject(
          with: Data(try #require(preview[endpoint]).utf8)) as? NSDictionary
      let sent =
        try JSONSerialization.jsonObject(
          with: try #require(spy.sent.first { $0.0 == endpoint }?.1)) as? NSDictionary
      #expect(shown == sent)
    }
  }
}

/// The constraints `telemetry-collector/src/telemetry_collector/schema.py`
/// validates, checked on encoded samples.
@Suite
struct TelemetryCollectorContractTests {
  private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
  }

  private func matches(_ value: Any?, _ pattern: String) -> Bool {
    guard let string = value as? String else { return false }
    return string.range(of: pattern, options: .regularExpression) != nil
  }

  @Test(
    "Health pings have the required keys and valid formats",
    arguments: [
      ("en-US", "2.14.3", .token), ("zh-Hans", "2.14.3-dev+abc", nil),
      ("pt-BR", nil, .sso), ("", "v3.0.1", ConnectionAuthMethod.none),
    ] as [(String, String?, ConnectionAuthMethod?)])
  func health(localization: String, backend: String?, auth: ConnectionAuthMethod?) throws {
    var env = environment(backend: backend, documents: nil)
    env.localization = localization
    env.auth = auth
    let data = try #require(
      try TelemetryPings.encodedPing(
        .health, environment: env, state: TelemetryState(), now: utc("2026-01-05")))
    let json = try object(data)

    let required: Set = [
      "channel", "app", "ios", "device", "lang", "client_cert", "custom_headers",
      "servers", "active_days_30", "install_age", "first_month", "first_week",
    ]
    let optional: Set = ["backend", "api", "docs", "auth"]
    #expect(json["auth"] as? String == auth?.rawValue)
    #expect(required.isSubset(of: json.keys))
    #expect(Set(json.keys).isSubset(of: required.union(optional)))

    #expect(matches(json["app"], #"^\d{1,4}(\.\d{1,4}){1,2}$"#))
    #expect(matches(json["ios"], #"^\d{1,3}\.\d{1,3}$"#))
    #expect(matches(json["lang"], "^[a-z]{2,3}$"))
    if let backend = json["backend"] {
      #expect(matches(backend, #"^(\d{1,4}\.\d{1,4}\.\d{1,4}|other)$"#))
    }
    // Real JSON booleans and integers, not strings.
    #expect(json["client_cert"] is Bool)
    #expect(json["custom_headers"] is Bool)
    #expect(CFGetTypeID(json["first_month"] as CFTypeRef) == CFBooleanGetTypeID())
    #expect(CFGetTypeID(json["first_week"] as CFTypeRef) == CFBooleanGetTypeID())
    #expect(CFGetTypeID(json["client_cert"] as CFTypeRef) == CFBooleanGetTypeID())
    let api = try #require(json["api"] as? NSNumber)
    #expect(CFGetTypeID(api) != CFBooleanGetTypeID())
    #expect((1...10_000).contains(api.intValue))
    #expect(data.count <= 4096)
  }

  @Test("Feature pings carry channel, day, features, available and optional errors")
  func feature() throws {
    let day = "2026-01-04"
    let all = Dictionary(uniqueKeysWithValues: TelemetryFeature.allCases.map { ($0, 50) })
    for state in [
      TelemetryState(activeDays: [day]),
      TelemetryState(
        pendingFeatures: [day: all], pendingErrors: [day: Set(TelemetryError.allCases)]),
    ] {
      let data = try #require(
        try TelemetryPings.encodedPing(
          .feature, environment: environment(), state: state, now: utc("2026-01-05")))
      let json = try object(data)
      let required: Set = ["channel", "day", "features", "available"]
      #expect(required.isSubset(of: json.keys))
      #expect(Set(json.keys).isSubset(of: required.union(["errors"])))
      #expect(matches(json["day"], #"^\d{4}-\d{2}-\d{2}$"#))
      let features = try #require(json["features"] as? [String: String])
      let available = try #require(json["available"] as? [String])
      #expect(features.count <= 64)
      #expect(available.count <= 64)
      #expect(((json["errors"] as? [String])?.count ?? 0) <= 64)
      #expect(data.count <= 4096)
    }
  }
}
