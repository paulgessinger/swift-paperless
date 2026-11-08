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
    let state = TelemetryState(pendingFeatures: [.search: 0, .filter: 3])
    let ping = TelemetryPings.featurePing(environment: environment(), state: state)
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
      pendingErrors: [.timeout, .tls], activeDays: ["2026-01-05"], installStamp: .existing)
    let ping = TelemetryPings.healthPing(
      environment: environment(backend: "2.14.3-dev"), state: state, now: utc("2026-01-05"))
    #expect(ping.ios == "18.3")
    #expect(ping.lang == "pt")
    #expect(ping.backend == "other")
    #expect(ping.docs == .under10k)
    #expect(ping.servers == .one)
    #expect(ping.active_days_30 == .one)
    #expect(ping.install_age == .existing)
    #expect(ping.errors == [.tls, .timeout])

    let json = try #require(
      try JSONSerialization.jsonObject(
        with: TelemetryPings.encodedPing(
          .health, environment: environment(), state: TelemetryState(), now: utc("2026-01-05")))
        as? [String: Any])
    // Empty errors are left out rather than sent as null or [].
    #expect(json["errors"] == nil)
    // Without bookkeeping yet: today counts as active, the stamp as existing.
    #expect(json["active_days_30"] as? String == "1")
    #expect(json["install_age"] as? String == "existing")
    // A connection without a recorded sign-in method sends no `auth`.
    #expect(json["auth"] == nil)
    #expect(
      Set(json.keys).isSubset(of: [
        "channel", "app", "ios", "device", "lang", "backend", "api", "docs", "auth",
        "client_cert", "custom_headers", "servers", "active_days_30", "install_age", "errors",
      ]))
  }

  @Test("The feature ping lists available features in schema order")
  func featurePing() throws {
    let ping = TelemetryPings.featurePing(
      environment: environment(), state: TelemetryState(pendingFeatures: [.notes: 12]))
    #expect(ping.features == [.notes: .many])
    #expect(ping.available == TelemetryFeature.allCases)

    let data = try TelemetryPings.encodedPing(
      .feature, environment: environment(), state: TelemetryState(), now: utc("2026-01-05"))
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect((json["features"] as? [String: Any])?.isEmpty == true)
    #expect(Set(json.keys) == ["channel", "features", "available"])
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
    TelemetryService(
      isConsented: { [consent] in consent.optedIn == true },
      transport: spy,
      defaults: defaults,
      now: { [clock] in clock.now },
      jitter: { .zero },
      sleep: { _ in })
  }

  private var storedKeys: [String] {
    TelemetryStorage.Key.allCases.map(\.rawValue).filter { defaults.object(forKey: $0) != nil }
  }

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

  @Test("Opted in: one health and one feature ping per UTC day")
  func oncePerDay() async throws {
    let service = makeService()
    consent.optedIn = true
    service.consentDidChange(hasConnection: true)

    await activate(service)
    await activate(service)
    clock.now = utc("2026-01-05", hour: 23)
    await activate(service)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 1)

    clock.now = utc("2026-01-06", hour: 0)
    await activate(service)
    #expect(spy.count(.health) == 2)
    #expect(spy.count(.feature) == 2)
  }

  @Test("An empty feature ping is still sent")
  func emptyFeaturePing() async throws {
    let service = makeService()
    consent.optedIn = true
    await activate(service)

    let body = try #require(spy.sent.first { $0.0 == .feature }?.1)
    let ping = try JSONDecoder().decode(FeaturePing.self, from: body)
    #expect(ping.features.isEmpty)
    #expect(ping.available == TelemetryFeature.allCases)
  }

  @Test("Recorded uses and errors are sent once, then reset")
  func pendingIsReset() async throws {
    let service = makeService()
    consent.optedIn = true
    service.record(.search)
    service.record(.search)
    service.record(.scanStarted)
    service.record(.auth)
    await activate(service)

    let feature = try JSONDecoder().decode(
      FeaturePing.self, from: try #require(spy.sent.first { $0.0 == .feature }?.1))
    #expect(feature.features == [.search: .few, .scanStarted: .one])
    let health = try JSONDecoder().decode(
      HealthPing.self, from: try #require(spy.sent.first { $0.0 == .health }?.1))
    #expect(health.errors == [.auth])
    #expect(health.install_age == .existing)
    #expect(health.active_days_30 == .one)

    let state = TelemetryStorage(defaults: defaults).load()
    #expect(state.pendingFeatures.isEmpty)
    #expect(state.pendingErrors.isEmpty)
  }

  @Test("A failed send is dropped and tried on the next activation")
  func failedSend() async {
    let service = makeService()
    consent.optedIn = true
    service.record(.notes)
    spy.failing = true
    await activate(service)
    #expect(spy.sent.isEmpty)
    #expect(TelemetryStorage(defaults: defaults).load().pendingFeatures == [.notes: 1])

    spy.failing = false
    await activate(service)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 1)
  }

  @Test("Opting in during onboarding stamps the day, later opt-ins are existing")
  func installStamp() {
    let service = makeService()
    consent.optedIn = true
    service.consentDidChange(hasConnection: false)
    #expect(TelemetryStorage(defaults: defaults).load().installStamp == .day("2026-01-05"))

    // A second change keeps the first stamp.
    service.consentDidChange(hasConnection: true)
    #expect(TelemetryStorage(defaults: defaults).load().installStamp == .day("2026-01-05"))

    consent.optedIn = false
    service.consentDidChange(hasConnection: true)
    consent.optedIn = true
    service.consentDidChange(hasConnection: true)
    #expect(TelemetryStorage(defaults: defaults).load().installStamp == .existing)
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

    consent.optedIn = false
    service.consentDidChange(hasConnection: true)
    #expect(storedKeys.isEmpty)

    clock.now = utc("2026-01-06")
    service.record(.filter)
    await activate(service)
    #expect(spy.count(.health) == 1)
    #expect(spy.count(.feature) == 1)
    #expect(storedKeys.isEmpty)
  }

  @Test("A service starting without consent removes leftover state")
  func clearsLeftovers() {
    defaults.set(["2026-01-01"], forKey: TelemetryStorage.Key.activeDays.rawValue)
    _ = makeService()
    #expect(storedKeys.isEmpty)
  }

  @Test("The disclosure renders the payloads the service sends")
  func preview() async throws {
    let service = makeService()
    consent.optedIn = true
    service.record(.savedView)
    service.appBecameActive { environment() }
    let preview = service.preview(environment: environment())
    await service.waitForPendingSends()

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
    let state = TelemetryState(pendingErrors: Set(TelemetryError.allCases))
    let data = try TelemetryPings.encodedPing(
      .health, environment: env, state: state, now: utc("2026-01-05"))
    let json = try object(data)

    let required: Set = [
      "channel", "app", "ios", "device", "lang", "client_cert", "custom_headers",
      "servers", "active_days_30", "install_age",
    ]
    let optional: Set = ["backend", "api", "docs", "auth", "errors"]
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
    #expect(CFGetTypeID(json["client_cert"] as CFTypeRef) == CFBooleanGetTypeID())
    let api = try #require(json["api"] as? NSNumber)
    #expect(CFGetTypeID(api) != CFBooleanGetTypeID())
    #expect((1...10_000).contains(api.intValue))
    #expect(((json["errors"] as? [String])?.count ?? 0) <= 64)
    #expect(data.count <= 4096)
  }

  @Test("Feature pings always carry channel, features and available")
  func feature() throws {
    let all = Dictionary(uniqueKeysWithValues: TelemetryFeature.allCases.map { ($0, 50) })
    for state in [TelemetryState(), TelemetryState(pendingFeatures: all)] {
      let data = try TelemetryPings.encodedPing(
        .feature, environment: environment(), state: state, now: utc("2026-01-05"))
      let json = try object(data)
      #expect(Set(json.keys) == ["channel", "features", "available"])
      let features = try #require(json["features"] as? [String: String])
      let available = try #require(json["available"] as? [String])
      #expect(features.count <= 64)
      #expect(available.count <= 64)
      #expect(data.count <= 4096)
    }
  }
}
