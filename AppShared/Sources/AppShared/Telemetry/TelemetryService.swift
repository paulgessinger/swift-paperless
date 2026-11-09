//
//  TelemetryService.swift
//  AppShared
//

import Common
import Foundation
import os

/// The process a ``TelemetryService`` records in.
///
/// The app owns the shared telemetry state and is the only process that
/// sends. Any other process writes only its own pending key, which the app
/// merges into its pings (see ``TelemetryStorage``).
public struct TelemetryProcess: RawRepresentable, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  /// The app, including the app intents it runs (the Upload Document
  /// shortcut).
  public static let app = TelemetryProcess(rawValue: "app")
  public static let shareExtension = TelemetryProcess(rawValue: "ShareExtension")

  /// ``app``, unless this process is an app extension: then the last
  /// component of the extension's bundle identifier, so an extension is never
  /// mistaken for the app.
  public static var current: TelemetryProcess {
    guard Bundle.main.bundleURL.pathExtension == "appex" else { return .app }
    let name = Bundle.main.bundleIdentifier?.split(separator: ".").last.map(String.init)
    return TelemetryProcess(rawValue: name ?? "extension")
  }
}

/// Records feature use and setup errors per UTC day, and sends the two pings:
/// health at most once per UTC day, and feature once for each completed day
/// it reports (see ``TelemetryState/featureReportDay(now:)``).
///
/// ``current`` is the production service in every process. The app and the
/// share extension both record into the app-group defaults; only the app
/// sends, and only the app changes or deletes state other than its own
/// pending uses. Every entry point checks consent first, so nothing is
/// recorded or stored before opt-in. Sends are fire-and-forget: a failed ping
/// is dropped and tried again on a later activation while it is still due.
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
  private let process: TelemetryProcess
  private let storage: TelemetryStorage
  private let now: @Sendable () -> Date

  private var sendTask: Task<Void, Never>?

  /// - Parameters:
  ///   - isConsented: Read at every entry point and again before each send.
  ///   - process: Decides which keys this service may write.
  public init(
    isConsented: @escaping @MainActor () -> Bool,
    transport: any TelemetryTransport,
    process: TelemetryProcess = .current,
    // The app group, so the share extension's uses reach the app's pings.
    defaults: UserDefaults = .group,
    now: @escaping @Sendable () -> Date = { Date() }
  ) {
    self.isConsented = isConsented
    self.transport = transport
    self.process = process
    storage = TelemetryStorage(defaults: defaults, process: process)
    self.now = now

    // Leftovers from an opt-out the app didn't observe, or from a build with
    // telemetry switched off. Only the app clears: it owns the state.
    if process == .app, !isConsented() { storage.clear() }
  }

  public func record(_ feature: TelemetryFeature) {
    updateOwnPending { pending, day in pending.features[day, default: [:]][feature, default: 0] += 1
    }
  }

  public func record(_ error: TelemetryError) {
    updateOwnPending { pending, day in pending.errors[day, default: []].insert(error) }
  }

  /// Applies `change` for today to this process's pending key, dropping days
  /// that were reported already or are outside the last 30.
  private func updateOwnPending(_ change: (inout TelemetryPending, String) -> Void) {
    guard isConsented() else { return }
    let now = now()
    var pending = storage.ownPending
    change(&pending, TelemetryDay.string(for: now))
    storage.ownPending = pending.pruned(now: now, lastReported: storage.featureLastReported)
  }

  /// Call in the app after the opt-in setting changed. Opting in writes the
  /// install stamp: the current day when no server is set up yet (first-run
  /// onboarding), `existing` otherwise. Opting out cancels any pending send and
  /// deletes all local telemetry state, that of other processes included.
  public func consentDidChange(hasConnection: Bool) {
    guard process == .app else { return }
    if isConsented() {
      guard storage.installStamp == nil else { return }
      storage.installStamp = hasConnection ? .existing : .day(TelemetryDay.string(for: now()))
    } else {
      sendTask?.cancel()
      sendTask = nil
      storage.clear()
    }
  }

  /// Call in the app when a scene becomes active with a connection
  /// established. Logs today as active and sends whichever pings are due.
  /// `environment` is gathered once, only if something is due.
  public func appBecameActive(
    environment: @escaping @MainActor () async -> TelemetryEnvironment
  ) {
    guard process == .app, isConsented() else { return }
    let now = now()
    // Opted in before this process could observe it, with a connection.
    if storage.installStamp == nil { storage.installStamp = .existing }
    let activeDays = storage.activeDays
    let recorded = TelemetryActiveDays.recording(activeDays, now: now)
    if recorded != activeDays { storage.activeDays = recorded }
    let pending = storage.ownPending
    let pruned = pending.pruned(now: now, lastReported: storage.featureLastReported)
    if pruned != pending { storage.ownPending = pruned }

    guard sendTask == nil, !dueEndpoints(storage.load(now: now), now: now).isEmpty else { return }
    sendTask = Task {
      await sendDuePings(environment: environment)
      sendTask = nil
    }
  }

  /// The pings as they would be sent right now, pretty-printed. The feature
  /// ping is absent when no completed day is due.
  public func preview(environment: TelemetryEnvironment) -> [TelemetryEndpoint: String] {
    let now = now()
    let state = storage.load(now: now)
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
    for endpoint in [TelemetryEndpoint.health, .feature] {
      let now = now()
      guard dueEndpoints(storage.load(now: now), now: now).contains(endpoint) else { continue }
      guard !Task.isCancelled, isConsented() else { return }
      await send(endpoint, environment: environment)
    }
  }

  private func send(_ endpoint: TelemetryEndpoint, environment: TelemetryEnvironment) async {
    let now = now()
    let sent = storage.load(now: now)
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
    switch endpoint {
    case .health:
      storage.healthLastSent = TelemetryDay.string(for: now)
      storage.healthLastMonth = TelemetryDay.month(for: now)
      storage.healthLastWeek = TelemetryDay.isoWeek(for: now)
    case .feature:
      // Pending days up to the reported one are skipped from now on and
      // pruned by their process's next write. The reported day is before
      // `now`'s day, so uses recorded while the request was in flight are kept.
      if let day = sent.featureReportDay(now: now) { storage.featureLastReported = day }
    }
  }
}
