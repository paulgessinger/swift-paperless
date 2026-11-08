import Foundation
import Testing

@testable import AppShared

/// The Swift vocabulary must match the schema the collector validates against.
@Suite
struct TelemetrySchemaTests {
  private struct Schema: Decodable {
    struct Buckets: Decodable {
      let count: [String]
      let docs: [String]
      let servers: [String]
      let active_days_30: [String]
      let install_age: [String]
    }

    let channels: [String]
    let buckets: Buckets
    let device: [String]
    let auth: [String]
    let features: [String]
    let errors: [String]
  }

  private static func loadSchema() throws -> Schema {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // AppSharedTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // AppShared
      .deletingLastPathComponent()  // repository root
      .appending(path: "telemetry-collector/telemetry-schema.json")
    return try JSONDecoder().decode(Schema.self, from: Data(contentsOf: url))
  }

  private static func raw<T: RawRepresentable & CaseIterable>(_: T.Type) -> [String]
  where T.RawValue == String {
    T.allCases.map(\.rawValue)
  }

  @Test("Enums and bucket strings match telemetry-schema.json")
  func matchesSchema() throws {
    let schema = try Self.loadSchema()
    #expect(Self.raw(TelemetryChannel.self) == schema.channels)
    #expect(Self.raw(TelemetryDevice.self) == schema.device)
    #expect(Self.raw(ConnectionAuthMethod.self) == schema.auth)
    #expect(Self.raw(TelemetryFeature.self) == schema.features)
    #expect(Self.raw(TelemetryError.self) == schema.errors)
    #expect(Self.raw(TelemetryCountBucket.self) == schema.buckets.count)
    #expect(Self.raw(TelemetryDocsBucket.self) == schema.buckets.docs)
    #expect(Self.raw(TelemetryServersBucket.self) == schema.buckets.servers)
    #expect(Self.raw(TelemetryActiveDaysBucket.self) == schema.buckets.active_days_30)
    #expect(Self.raw(TelemetryInstallAgeBucket.self) == schema.buckets.install_age)
  }
}
