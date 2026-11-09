//
//  TelemetryStorage.swift
//  AppShared
//

import Foundation

/// The `UserDefaults` keys holding telemetry state, shared by every process in
/// the app group. Written only while opted in.
///
/// Each key has a single writer, so processes never overwrite each other's
/// updates: ``Key`` is written by the app only, and each process writes only
/// its own pending key (``pendingKeyPrefix`` plus its name). Every setter
/// writes one key.
struct TelemetryStorage {
  /// The app's keys.
  enum Key: String, CaseIterable {
    case healthLastSent = "telemetryHealthLastSent"
    case featureLastReported = "telemetryFeatureLastReported"
    case activeDays = "telemetryActiveDays"
    case installStamp = "telemetryInstallStamp"
  }

  /// Followed by a ``TelemetryProcess`` name. The app reads every key with
  /// this prefix, so a new recording process needs no change here.
  static let pendingKeyPrefix = "telemetryPending."

  let defaults: UserDefaults
  let process: TelemetryProcess

  // MARK: App keys

  var healthLastSent: String? {
    get { defaults.string(forKey: Key.healthLastSent.rawValue) }
    nonmutating set { set(newValue, .healthLastSent) }
  }

  /// Read by every process to prune its pending key.
  var featureLastReported: String? {
    get { defaults.string(forKey: Key.featureLastReported.rawValue) }
    nonmutating set { set(newValue, .featureLastReported) }
  }

  var activeDays: Set<String> {
    get { Set(defaults.stringArray(forKey: Key.activeDays.rawValue) ?? []) }
    nonmutating set { set(newValue.isEmpty ? nil : newValue.sorted(), .activeDays) }
  }

  var installStamp: TelemetryInstallStamp? {
    get {
      defaults.string(forKey: Key.installStamp.rawValue)
        .flatMap(TelemetryInstallStamp.init(storedValue:))
    }
    nonmutating set { set(newValue?.storedValue, .installStamp) }
  }

  // MARK: Pending

  /// This process's recorded uses and errors.
  var ownPending: TelemetryPending {
    get { Self.decode(defaults.dictionary(forKey: pendingKey)) }
    nonmutating set {
      if newValue.isEmpty {
        defaults.removeObject(forKey: pendingKey)
      } else {
        defaults.set(Self.encode(newValue), forKey: pendingKey)
      }
    }
  }

  /// The app's keys and the pending uses of every process, without days that
  /// were reported already or are outside the last 30.
  func load(now: Date) -> TelemetryState {
    let lastReported = featureLastReported
    let pending = TelemetryPending.merged(
      pendingKeys.map { Self.decode(defaults.dictionary(forKey: $0)) }
    ).pruned(now: now, lastReported: lastReported)
    return TelemetryState(
      healthLastSent: healthLastSent,
      featureLastReported: lastReported,
      pendingFeatures: pending.features,
      pendingErrors: pending.errors,
      activeDays: activeDays,
      installStamp: installStamp)
  }

  /// Removes every telemetry key, those of other processes included.
  func clear() {
    for key in storedKeys {
      defaults.removeObject(forKey: key)
    }
  }

  /// The telemetry keys that are present.
  var storedKeys: [String] {
    Key.allCases.map(\.rawValue).filter { defaults.object(forKey: $0) != nil } + pendingKeys
  }

  private var pendingKey: String { Self.pendingKeyPrefix + process.rawValue }

  private var pendingKeys: [String] {
    defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(Self.pendingKeyPrefix) }.sorted()
  }

  private func set(_ value: Any?, _ key: Key) {
    assert(process == .app, "Only the app writes \(key.rawValue)")
    if let value {
      defaults.set(value, forKey: key.rawValue)
    } else {
      defaults.removeObject(forKey: key.rawValue)
    }
  }

  // Stored as `["features": [day: [feature: count]], "errors": [day: [error]]]`.

  private static func encode(_ pending: TelemetryPending) -> [String: Any] {
    [
      "features": pending.features.mapValues { counts in
        Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value) })
      },
      "errors": pending.errors.mapValues { $0.map(\.rawValue).sorted() },
    ]
  }

  private static func decode(_ stored: [String: Any]?) -> TelemetryPending {
    let features = (stored?["features"] as? [String: [String: Int]])?.mapValues { counts in
      counts.reduce(into: [TelemetryFeature: Int]()) { result, entry in
        if let feature = TelemetryFeature(rawValue: entry.key) { result[feature] = entry.value }
      }
    }
    let errors = (stored?["errors"] as? [String: [String]])?
      .mapValues { Set($0.compactMap(TelemetryError.init(rawValue:))) }
    return TelemetryPending(features: features ?? [:], errors: errors ?? [:])
  }
}
