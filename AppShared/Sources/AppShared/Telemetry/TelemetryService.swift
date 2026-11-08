//
//  TelemetryService.swift
//  AppShared
//

import Common
import Foundation
import os

/// Records feature use and setup errors per UTC day, and sends the two pings:
/// health at most once per UTC day, and feature once for each completed day
/// it reports (see ``TelemetryState/featureReportDay(now:)``).
///
/// ``current`` is the production service in every process. The app and the
/// share extension both record into the app-group defaults; only the app
/// sends. Every entry point checks consent first, so nothing is recorded or
/// stored before opt-in. Sends are fire-and-forget: a failed ping is dropped
/// and tried again on a later activation while it is still due.
@MainActor
public final class TelemetryService {
  public static let current = TelemetryService(
    isConsented: { AppFeatures.enabled(.telemetry) && AppSettings.shared.telemetryOptIn == true },
    transport: URLSessionTelemetryTransport(baseURL: TelemetryCollector.baseURL))

  public static func record(_ feature: TelemetryFeature) {
    current.record(feature)
  }

  /// Records the setup-problem class of `error`, if it has one.
  public static func record(error: any Error) {
    guard let error = TelemetryError(classifying: error) else { return }
    current.record(error)
  }

  public static func record(_ error: TelemetryError) {
    current.record(error)
  }

  private let isConsented: @MainActor () -> Bool
  private let transport: any TelemetryTransport
  private let storage: TelemetryStorage
  private let now: @Sendable () -> Date
  private let jitter: @Sendable () -> Duration
  private let sleep: @Sendable (Duration) async throws -> Void

  private var sendTask: Task<Void, Never>?

  /// - Parameters:
  ///   - isConsented: Read at every entry point and again before each send.
  ///   - jitter: The delay between the two pings, so the collector can't pair
  ///     them by arrival time.
  public init(
    isConsented: @escaping @MainActor () -> Bool,
    transport: any TelemetryTransport,
    // The app group, so the share extension's uses reach the app's pings.
    defaults: UserDefaults = .group,
    now: @escaping @Sendable () -> Date = { Date() },
    jitter: @escaping @Sendable () -> Duration = { .seconds(Int.random(in: 5...60)) },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
  ) {
    self.isConsented = isConsented
    self.transport = transport
    storage = TelemetryStorage(defaults: defaults)
    self.now = now
    self.jitter = jitter
    self.sleep = sleep

    // Leftovers from an opt-out this process didn't observe.
    if !isConsented() { storage.clear() }
  }

  public func record(_ feature: TelemetryFeature) {
    guard isConsented() else { return }
    let now = now()
    var state = storage.load()
    state.pendingFeatures[TelemetryDay.string(for: now), default: [:]][feature, default: 0] += 1
    state.prunePending(now: now)
    storage.save(state)
  }

  public func record(_ error: TelemetryError) {
    guard isConsented() else { return }
    let now = now()
    var state = storage.load()
    state.pendingErrors[TelemetryDay.string(for: now), default: []].insert(error)
    state.prunePending(now: now)
    storage.save(state)
  }

  /// Call after the opt-in setting changed. Opting in writes the install
  /// stamp: the current day when no server is set up yet (first-run
  /// onboarding), `existing` otherwise. Opting out cancels any pending send and
  /// deletes all local telemetry state.
  public func consentDidChange(hasConnection: Bool) {
    if isConsented() {
      var state = storage.load()
      guard state.installStamp == nil else { return }
      state.installStamp = hasConnection ? .existing : .day(TelemetryDay.string(for: now()))
      storage.save(state)
    } else {
      sendTask?.cancel()
      sendTask = nil
      storage.clear()
    }
  }

  /// Call when a scene becomes active with a connection established. Logs
  /// today as active and sends whichever pings are due.
  /// `environment` is gathered once, only if something is due.
  public func appBecameActive(
    environment: @escaping @MainActor () async -> TelemetryEnvironment
  ) {
    guard isConsented() else { return }
    let now = now()
    var state = storage.load()
    // Opted in before this process could observe it, with a connection.
    if state.installStamp == nil { state.installStamp = .existing }
    state.activeDays = TelemetryActiveDays.recording(state.activeDays, now: now)
    state.prunePending(now: now)
    storage.save(state)

    guard sendTask == nil, !dueEndpoints(state, now: now).isEmpty else { return }
    sendTask = Task {
      await sendDuePings(environment: environment)
      sendTask = nil
    }
  }

  /// The pings as they would be sent right now, pretty-printed. The feature
  /// ping is absent when no completed day is due.
  public func preview(environment: TelemetryEnvironment) -> [TelemetryEndpoint: String] {
    let state = storage.load()
    let now = now()
    var result: [TelemetryEndpoint: String] = [:]
    for endpoint in TelemetryEndpoint.allCases {
      if let data = try? TelemetryPings.encodedPing(
        endpoint, environment: environment, state: state, now: now, pretty: true)
      {
        result[endpoint] = String(decoding: data, as: UTF8.self)
      }
    }
    return result
  }

  /// Waits for an in-flight send. For tests.
  func waitForPendingSends() async {
    await sendTask?.value
  }

  // MARK: Sending

  private func dueEndpoints(_ state: TelemetryState, now: Date) -> [TelemetryEndpoint] {
    var due: [TelemetryEndpoint] = []
    if TelemetryDay.shouldSend(lastSent: state.healthLastSent, now: now) { due.append(.health) }
    if state.featureReportDay(now: now) != nil { due.append(.feature) }
    return due
  }

  private func sendDuePings(
    environment: @MainActor () async -> TelemetryEnvironment
  ) async {
    let environment = await environment()
    // Random order, so neither ping's arrival marks the other's.
    let order: [TelemetryEndpoint] = Bool.random() ? [.health, .feature] : [.feature, .health]
    var isFirst = true
    for endpoint in order {
      guard dueEndpoints(storage.load(), now: now()).contains(endpoint) else { continue }
      if !isFirst {
        guard (try? await sleep(jitter())) != nil else { return }
      }
      isFirst = false
      guard !Task.isCancelled, isConsented() else { return }
      await send(endpoint, environment: environment)
    }
  }

  private func send(_ endpoint: TelemetryEndpoint, environment: TelemetryEnvironment) async {
    let now = now()
    let sent = storage.load()
    do {
      guard
        let body = try TelemetryPings.encodedPing(
          endpoint, environment: environment, state: sent, now: now)
      else { return }
      try await transport.send(body, to: endpoint)
    } catch {
      Logger.telemetry.info(
        "Telemetry \(endpoint.rawValue, privacy: .public) ping dropped: \(error)")
      return
    }

    // An opt-out during the request has already deleted the state.
    guard isConsented() else { return }
    var state = storage.load()
    switch endpoint {
    case .health:
      state.healthLastSent = TelemetryDay.string(for: now)
    case .feature:
      // The reported day is before `now`'s day, so uses recorded while the
      // request was in flight land on a later day and are kept.
      if let day = sent.featureReportDay(now: now) { state.didReport(day: day) }
    }
    storage.save(state)
  }
}
