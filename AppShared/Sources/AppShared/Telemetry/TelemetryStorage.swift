//
//  TelemetryStorage.swift
//  AppShared
//

import Foundation

/// The `UserDefaults` keys holding ``TelemetryState``. Written only while opted
/// in; ``clear()`` removes every one of them.
struct TelemetryStorage {
  enum Key: String, CaseIterable {
    case healthLastSent = "telemetryHealthLastSent"
    case featureLastSent = "telemetryFeatureLastSent"
    case pendingFeatures = "telemetryPendingFeatures"
    case pendingErrors = "telemetryPendingErrors"
    case activeDays = "telemetryActiveDays"
    case installStamp = "telemetryInstallStamp"
  }

  let defaults: UserDefaults

  func load() -> TelemetryState {
    let features = (defaults.dictionary(forKey: Key.pendingFeatures.rawValue) as? [String: Int])?
      .reduce(into: [TelemetryFeature: Int]()) { result, entry in
        if let feature = TelemetryFeature(rawValue: entry.key) { result[feature] = entry.value }
      }
    let errors = defaults.stringArray(forKey: Key.pendingErrors.rawValue)?
      .compactMap(TelemetryError.init(rawValue:))

    return TelemetryState(
      healthLastSent: defaults.string(forKey: Key.healthLastSent.rawValue),
      featureLastSent: defaults.string(forKey: Key.featureLastSent.rawValue),
      pendingFeatures: features ?? [:],
      pendingErrors: Set(errors ?? []),
      activeDays: Set(defaults.stringArray(forKey: Key.activeDays.rawValue) ?? []),
      installStamp: defaults.string(forKey: Key.installStamp.rawValue)
        .flatMap(TelemetryInstallStamp.init(storedValue:)))
  }

  func save(_ state: TelemetryState) {
    set(state.healthLastSent, .healthLastSent)
    set(state.featureLastSent, .featureLastSent)
    set(
      Dictionary(uniqueKeysWithValues: state.pendingFeatures.map { ($0.key.rawValue, $0.value) }),
      .pendingFeatures)
    set(state.pendingErrors.map(\.rawValue).sorted(), .pendingErrors)
    set(state.activeDays.sorted(), .activeDays)
    set(state.installStamp?.storedValue, .installStamp)
  }

  func clear() {
    for key in Key.allCases {
      defaults.removeObject(forKey: key.rawValue)
    }
  }

  /// Whether any telemetry key is present.
  var isEmpty: Bool {
    Key.allCases.allSatisfy { defaults.object(forKey: $0.rawValue) == nil }
  }

  private func set(_ value: Any?, _ key: Key) {
    if let value {
      defaults.set(value, forKey: key.rawValue)
    } else {
      defaults.removeObject(forKey: key.rawValue)
    }
  }
}
