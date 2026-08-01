//
//  SettingsStoreMigrationTest.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import Foundation
import Testing

@testable import Common

private enum Fixture {
  /// Encodes as a JSON string, like SortField and FilterState.SearchMode.
  enum Mode: String, Codable, Sendable, Equatable {
    case titleContent
    case advanced
  }

  /// Encodes as a JSON bool, like DataModel.SortOrder.
  struct Reversed: Codable, Sendable, Equatable {
    var reversed: Bool
    init(_ reversed: Bool) { self.reversed = reversed }
    init(from decoder: any Decoder) throws {
      reversed = try decoder.singleValueContainer().decode(Bool.self)
    }
    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(reversed)
    }
  }

  struct Composite: Codable, Sendable, Equatable {
    var components: [String]
  }

  static let flag = SettingKey("flag", default: true)
  static let mode = SettingKey("mode", default: Mode.titleContent)
  static let order = SettingKey("order", default: Reversed(false))
  static let composite = SettingKey("composite", default: Composite(components: ["a"]))
  static let text = SettingKey("text", default: "")
  static let optional = SettingKey<Int?>("optional", default: nil)
}

private struct Suites: ~Copyable {
  let device: UserDefaults
  let store: SettingsStore
  private let name: String

  init() {
    name = "SettingsStoreMigrationTest.\(UUID().uuidString)"
    device = UserDefaults(suiteName: name)!
    store = SettingsStore(suites: [.device: device])
  }

  /// Writes a value the way the app stored settings before the migration.
  func writeLegacy(_ value: some Encodable, key: String) {
    device.set(try! JSONEncoder().encode(value), forKey: key)
  }

  deinit { device.removePersistentDomain(forName: name) }
}

@Suite("SettingsStore native storage")
struct SettingsStoreMigrationTest {
  @Test("scalars are written as native types, not as JSON blobs")
  func nativeWrites() {
    let suites = Suites()

    suites.store[Fixture.flag] = false
    suites.store[Fixture.mode] = .advanced
    suites.store[Fixture.order] = .init(true)

    #expect(suites.device.object(forKey: "flag") as? Bool == false)
    #expect(suites.device.object(forKey: "mode") as? String == "advanced")
    #expect(suites.device.object(forKey: "order") as? Bool == true)

    // ...which is what makes them readable the ordinary way
    #expect(suites.device.string(forKey: "mode") == "advanced")
  }

  @Test("composite values stay JSON")
  func compositeStaysJSON() {
    let suites = Suites()

    suites.store[Fixture.composite] = .init(components: ["b", "c"])

    let stored = suites.device.object(forKey: "composite")
    #expect(stored is Data)
    #expect(suites.store[Fixture.composite] == .init(components: ["b", "c"]))
  }

  @Test("a value stored by the previous build is read and rewritten natively")
  func migratesOnRead() {
    let suites = Suites()

    suites.writeLegacy(Fixture.Mode.advanced, key: "mode")
    suites.writeLegacy(false, key: "flag")
    #expect(suites.device.object(forKey: "mode") is Data)

    #expect(suites.store[Fixture.mode] == .advanced)
    #expect(suites.store[Fixture.flag] == false)

    #expect(suites.device.object(forKey: "mode") as? String == "advanced")
    #expect(suites.device.object(forKey: "flag") as? Bool == false)

    // The rewrite did not change what the value reads back as
    let other = SettingsStore(suites: [.device: suites.device])
    #expect(other[Fixture.mode] == .advanced)
    #expect(other[Fixture.flag] == false)
  }

  @Test("a legacy composite value is left as JSON")
  func compositeNotMigrated() {
    let suites = Suites()

    suites.writeLegacy(Fixture.Composite(components: ["x"]), key: "composite")
    #expect(suites.store[Fixture.composite] == .init(components: ["x"]))
    #expect(suites.device.object(forKey: "composite") is Data)
  }

  @Test("strings needing escaping survive the round trip")
  func escaping() {
    let suites = Suites()

    let awkward = #"quote " backslash \ newline"# + "\n\u{1F600}"
    suites.store[Fixture.text] = awkward

    #expect(suites.device.object(forKey: "text") as? String == awkward)
    #expect(suites.store[Fixture.text] == awkward)

    let other = SettingsStore(suites: [.device: suites.device])
    #expect(other[Fixture.text] == awkward)
  }

  @Test("an optional value still round-trips")
  func optionals() {
    let suites = Suites()

    suites.store[Fixture.optional] = 42
    #expect(suites.store[Fixture.optional] == 42)

    suites.store[Fixture.optional] = nil
    let other = SettingsStore(suites: [.device: suites.device])
    #expect(other[Fixture.optional] == nil)
  }

  @Test("a corrupt native value falls back to the default")
  func corruptNative() {
    let suites = Suites()

    // A string that is not one of the enum's cases
    suites.device.set("nonsense", forKey: "mode")
    #expect(suites.store[Fixture.mode] == .titleContent)
  }
}
