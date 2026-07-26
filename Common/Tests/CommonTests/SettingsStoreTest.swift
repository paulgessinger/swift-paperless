//
//  SettingsStoreTest.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

@testable import Common
import Foundation
import Testing

private enum Fixture {
  enum Mode: String, Codable, Sendable, Equatable {
    case titleContent
    case advanced
  }

  struct Composite: Codable, Sendable, Equatable {
    var components: [String]
    var enabled: Bool
  }

  static let flag = SettingKey("flag", default: true)
  static let mode = SettingKey("mode", default: Mode.titleContent)
  static let composite = SettingKey(
    "composite", default: Composite(components: ["a"], enabled: false))
  static let sharedFlag = SettingKey("sharedFlag", default: false, scope: .shared)
  static let optional = SettingKey<Int?>("optional", default: nil)
  static let optionalWithDefault = SettingKey<Int?>("optionalWithDefault", default: 7)
}

/// Gives each test its own pair of suites, so nothing leaks between tests or
/// into the developer's actual preferences.
private struct Suites: ~Copyable {
  let device: UserDefaults
  let shared: UserDefaults
  let store: SettingsStore

  private let deviceName: String
  private let sharedName: String

  init() {
    deviceName = "SettingsStoreTest.device.\(UUID().uuidString)"
    sharedName = "SettingsStoreTest.shared.\(UUID().uuidString)"
    device = UserDefaults(suiteName: deviceName)!
    shared = UserDefaults(suiteName: sharedName)!
    store = SettingsStore(suites: [.device: device, .shared: shared])
  }

  deinit {
    device.removePersistentDomain(forName: deviceName)
    shared.removePersistentDomain(forName: sharedName)
  }
}

@Suite("SettingsStore")
struct SettingsStoreTest {
  @Test("unset keys read as their declared default")
  func defaults() {
    let suites = Suites()
    #expect(suites.store[Fixture.flag] == true)
    #expect(suites.store[Fixture.mode] == .titleContent)
    #expect(suites.store[Fixture.composite].components == ["a"])
    #expect(suites.store[Fixture.optional] == nil)
  }

  @Test("values round-trip through the suite")
  func roundTrip() {
    let suites = Suites()

    suites.store[Fixture.flag] = false
    suites.store[Fixture.mode] = .advanced
    suites.store[Fixture.composite] = .init(components: ["b", "c"], enabled: true)
    suites.store[Fixture.optional] = 42

    #expect(suites.store[Fixture.flag] == false)
    #expect(suites.store[Fixture.mode] == .advanced)
    #expect(suites.store[Fixture.composite] == .init(components: ["b", "c"], enabled: true))
    #expect(suites.store[Fixture.optional] == 42)

    // A second store over the same suites sees the persisted values, i.e. they
    // really went to disk rather than only into the cache.
    let other = SettingsStore(suites: [.device: suites.device, .shared: suites.shared])
    #expect(other[Fixture.flag] == false)
    #expect(other[Fixture.mode] == .advanced)
    #expect(other[Fixture.optional] == 42)
  }

  @Test("an optional value can be set back to nil, which is not the default")
  func optionalNil() {
    let suites = Suites()
    #expect(suites.store[Fixture.optionalWithDefault] == 7)

    suites.store[Fixture.optionalWithDefault] = nil
    // Cached...
    #expect(suites.store[Fixture.optionalWithDefault] == nil)
    // ...and persisted: an explicit nil is not the same as "never set"
    let other = SettingsStore(suites: [.device: suites.device, .shared: suites.shared])
    #expect(other[Fixture.optionalWithDefault] == nil)

    suites.store.remove(Fixture.optionalWithDefault)
    #expect(suites.store[Fixture.optionalWithDefault] == 7)
  }

  @Test("the scope decides which suite is written")
  func scopeRouting() {
    let suites = Suites()

    suites.store[Fixture.flag] = false
    suites.store[Fixture.sharedFlag] = true

    #expect(suites.device.object(forKey: "flag") != nil)
    #expect(suites.shared.object(forKey: "flag") == nil)

    #expect(suites.shared.object(forKey: "sharedFlag") != nil)
    #expect(suites.device.object(forKey: "sharedFlag") == nil)
  }

  @Test("removing a value restores the default")
  func remove() {
    let suites = Suites()

    suites.store[Fixture.flag] = false
    #expect(suites.store[Fixture.flag] == false)

    suites.store.remove(Fixture.flag)
    #expect(suites.store[Fixture.flag] == true)
    #expect(suites.device.object(forKey: "flag") == nil)
  }

  @Test("a value written behind the store's back is picked up")
  func externalWrite() {
    let suites = Suites()

    // Prime the cache
    #expect(suites.store[Fixture.mode] == .titleContent)

    suites.device.set(try! JSONEncoder().encode(Fixture.Mode.advanced), forKey: "mode")

    #expect(suites.store[Fixture.mode] == .advanced)
  }

  @Test("undecodable data falls back to the default instead of trapping")
  func corruptValue() {
    let suites = Suites()

    suites.device.set(Data("not json".utf8), forKey: "mode")
    #expect(suites.store[Fixture.mode] == .titleContent)

    // A non-Data value (e.g. written by an older @AppStorage) is tolerated too
    suites.device.set("advanced", forKey: "mode")
    #expect(suites.store[Fixture.mode] == .titleContent)
  }

  @Test("the on-disk format is the JSON the app has always written")
  func storageFormat() {
    let suites = Suites()

    suites.store[Fixture.mode] = .advanced

    let data = suites.device.object(forKey: "mode") as? Data
    #expect(data == Data(#""advanced""#.utf8))

    // ...and a value written by the previous UserDefaultsBacked wrapper reads back
    suites.device.set(try! JSONEncoder().encode(true), forKey: "flag")
    #expect(suites.store[Fixture.flag] == true)
  }
}
