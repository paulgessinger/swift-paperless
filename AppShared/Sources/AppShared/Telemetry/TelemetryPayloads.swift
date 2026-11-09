//
//  TelemetryPayloads.swift
//  AppShared
//

import Foundation

/// The body of `POST /t/health`. The optional fields are left out of the JSON
/// when unknown; the collector requires all others.
public struct HealthPing: Codable, Equatable, Sendable {
  public var channel: TelemetryChannel
  public var app: String
  public var ios: String
  public var device: TelemetryDevice
  public var lang: String
  public var backend: String?
  public var api: UInt?
  public var docs: TelemetryDocsBucket?
  /// `nil` for connections that predate recording the sign-in method.
  public var auth: ConnectionAuthMethod?
  public var client_cert: Bool
  public var custom_headers: Bool
  public var servers: TelemetryServersBucket
  public var active_days_30: TelemetryActiveDaysBucket
  public var install_age: TelemetryInstallAgeBucket
  /// No health ping was sent successfully earlier in this UTC month.
  public var first_month: Bool
  /// No health ping was sent successfully earlier in this ISO week (UTC).
  public var first_week: Bool
}

/// The body of `POST /t/feature`: one completed UTC day. Sent for every
/// reported day even when `features` is empty, so the ping count is a
/// denominator.
public struct FeaturePing: Codable, Equatable, Sendable {
  public var channel: TelemetryChannel
  /// The UTC day the counts belong to, `yyyy-MM-dd`.
  public var day: String
  public var features: [TelemetryFeature: TelemetryCountBucket]
  /// Sorted in schema order.
  public var available: [TelemetryFeature]
  /// The setup errors hit that day, in schema order; `nil` rather than empty.
  public var errors: [TelemetryError]?
}

public enum TelemetryEndpoint: String, CaseIterable, Sendable {
  case health
  case feature

  public var path: String { "/t/\(rawValue)" }
}

public enum TelemetryCollector {
  /// Compiled in, for every channel: debug builds report as `dev`.
  public static let baseURL = URL(string: "https://telemetry.swift-paperless.app")!
}

public enum TelemetryEncoding {
  /// The encoder for both what is sent and what "What's sent" shows: the
  /// disclosure only adds indentation.
  public static func encode(_ value: some Encodable, pretty: Bool = false) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = pretty ? [.sortedKeys, .prettyPrinted] : [.sortedKeys]
    return try encoder.encode(value)
  }
}
