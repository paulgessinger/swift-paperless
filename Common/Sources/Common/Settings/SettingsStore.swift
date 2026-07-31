//
//  SettingsStore.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation
import os

/// Persists ``SettingKey`` values, routing each key to the suite its
/// ``SettingScope`` asks for.
///
/// The store is deliberately free of actor isolation: `FilterState.default` is
/// a nonisolated static and has to be able to read the sort/search defaults.
/// Decoded values are cached behind a lock and dropped whenever `UserDefaults`
/// reports a change, so a read is a dictionary lookup rather than a `JSONDecoder`
/// allocation.
///
/// Values are stored as JSON `Data`, which is the format the app has always
/// written.
public final class SettingsStore: @unchecked Sendable {
  private let suites: [SettingScope: UserDefaults]

  /// Boxed so that a cached `nil` (for a key whose `Value` is an optional) is
  /// distinguishable from an absent cache entry: casting a plain `Any?` to an
  /// optional `Value` succeeds for both.
  private struct Box {
    let value: Any
  }

  private let lock = NSLock()
  private var cache: [String: Box] = [:]

  private var observer: NSObjectProtocol?

  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "swift-paperless", category: "Settings")

  public init(suites: [SettingScope: UserDefaults]) {
    self.suites = suites

    // Someone else in the process (or the ShareExtension, for the shared
    // suite) may have written a value we have cached.
    observer = NotificationCenter.default.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: nil,
      queue: nil
    ) { [weak self] _ in
      self?.invalidate()
    }
  }

  deinit {
    if let observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func suite(for scope: SettingScope) -> UserDefaults {
    guard let suite = suites[scope] else {
      Self.logger.error(
        "No suite configured for scope \(scope.rawValue, privacy: .public), using standard")
      return .standard
    }
    return suite
  }

  public func invalidate() {
    lock.lock()
    defer { lock.unlock() }
    cache.removeAll()
  }

  public subscript<Value>(key: SettingKey<Value>) -> Value {
    get { value(for: key) }
    set { set(newValue, for: key) }
  }

  public func value<Value>(for key: SettingKey<Value>) -> Value {
    lock.lock()
    let cached = cache[key.name]
    lock.unlock()

    if let cached, let value = cached.value as? Value {
      return value
    }

    let value = decode(key)

    lock.lock()
    cache[key.name] = Box(value: value)
    lock.unlock()

    return value
  }

  private func decode<Value>(_ key: SettingKey<Value>) -> Value {
    guard let data = suite(for: key.scope).object(forKey: key.name) as? Data else {
      return key.defaultValue
    }

    do {
      let value = try JSONDecoder().decode(Value.self, from: data)
      Self.logger.trace(
        "Setting \(key.name, privacy: .public) read: \(String(describing: value), privacy: .private)"
      )
      return value
    } catch {
      Self.logger.error(
        "Setting \(key.name, privacy: .public) could not be decoded, using default: \(error)")
      return key.defaultValue
    }
  }

  public func set<Value>(_ value: Value, for key: SettingKey<Value>) {
    Self.logger.trace(
      "Setting \(key.name, privacy: .public) written: \(String(describing: value), privacy: .private)"
    )

    do {
      let data = try JSONEncoder().encode(value)
      // Outside the lock: writing posts didChangeNotification synchronously,
      // which invalidates the cache.
      suite(for: key.scope).set(data, forKey: key.name)
    } catch {
      Self.logger.error("Setting \(key.name, privacy: .public) could not be encoded: \(error)")
      return
    }

    lock.lock()
    cache[key.name] = Box(value: value)
    lock.unlock()
  }

  /// Removes the stored value, so subsequent reads see the key's default.
  public func remove<Value>(_ key: SettingKey<Value>) {
    Self.logger.info("Setting \(key.name, privacy: .public) removed")
    suite(for: key.scope).removeObject(forKey: key.name)

    lock.lock()
    cache.removeValue(forKey: key.name)
    lock.unlock()
  }
}
