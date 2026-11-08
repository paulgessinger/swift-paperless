//
//  TelemetryVocabulary.swift
//  AppShared
//
//  The closed value sets a telemetry ping may contain. Every raw value must
//  match `telemetry-collector/telemetry-schema.json`; `TelemetrySchemaTests`
//  fails when they drift.
//

import Foundation

/// The distribution channel a ping is counted under.
public enum TelemetryChannel: String, Codable, CaseIterable, Sendable {
  case appstore
  case testflight
  /// Debug and simulator builds. Only ever sent to the dev collector.
  case dev

  public init(_ configuration: AppConfiguration) {
    switch configuration {
    case .AppStore: self = .appstore
    case .TestFlight: self = .testflight
    case .Debug, .Simulator: self = .dev
    }
  }
}

/// A user-facing feature whose daily use is counted.
public enum TelemetryFeature: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
  /// A saved view was applied to the document list.
  case savedView = "saved_view"
  /// A search was started: the search text went from empty to non-empty.
  case search
  /// A filter rule of the document list changed.
  case filter
  /// A document's metadata was saved from the detail view.
  case documentEdit = "document_edit"
  /// A document's file was handed to the share sheet.
  case documentShare = "document_share"
  case scanStarted = "scan_started"
  case scanUploaded = "scan_uploaded"
  case importStarted = "import_started"
  case importUploaded = "import_uploaded"
  /// A document scanned over the network (eSCL) was uploaded.
  case networkScanUploaded = "network_scan_uploaded"
  /// A document was uploaded from the share extension.
  case shareExtensionUploaded = "share_extension_uploaded"
  /// A document was uploaded by the Upload Document shortcut action.
  case shortcutUploaded = "shortcut_uploaded"
  /// A note was added to a document.
  case notes
}

/// A class of setup problem, recorded at most once per day each.
public enum TelemetryError: String, Codable, CaseIterable, Sendable {
  case tls
  case auth
  case timeout
  case unreachable
  case backendTooOld = "backend_too_old"
  case other
}

public enum TelemetryDevice: String, Codable, CaseIterable, Sendable {
  case iPhone
  case iPad
  /// The iPad app running on an Apple Silicon Mac.
  case Mac
}

// MARK: - Buckets

/// A count of uses. Zero has no bucket: the key is left out instead.
public enum TelemetryCountBucket: String, Codable, CaseIterable, Sendable {
  case one = "1"
  case few = "2-9"
  case many = "10+"

  public init?(count: Int) {
    switch count {
    case ..<1: return nil
    case 1: self = .one
    case 2...9: self = .few
    default: self = .many
    }
  }
}

/// The active server's document count.
public enum TelemetryDocsBucket: String, Codable, CaseIterable, Sendable {
  case under1k = "<1k"
  case under10k = "1k-10k"
  case atLeast10k = "10k+"

  public init(count: UInt) {
    switch count {
    case ..<1000: self = .under1k
    case ..<10000: self = .under10k
    default: self = .atLeast10k
    }
  }
}

/// How many server connections are configured.
public enum TelemetryServersBucket: String, Codable, CaseIterable, Sendable {
  case one = "1"
  case several = "2+"

  /// A ping implies an active connection, so fewer than one counts as one.
  public init(count: Int) {
    self = count > 1 ? .several : .one
  }
}

/// On how many UTC days of the last 30 the app became active.
public enum TelemetryActiveDaysBucket: String, Codable, CaseIterable, Sendable {
  case one = "1"
  case upToWeek = "2-7"
  case upTo20 = "8-20"
  case atLeast21 = "21+"

  public init?(count: Int) {
    switch count {
    case ..<1: return nil
    case 1: self = .one
    case 2...7: self = .upToWeek
    case 8...20: self = .upTo20
    default: self = .atLeast21
    }
  }
}

/// Time since the local install stamp, or `existing` when the user opted in
/// after the app was already set up.
public enum TelemetryInstallAgeBucket: String, Codable, CaseIterable, Sendable {
  case underWeek = "<7d"
  case underMonth = "<30d"
  case underYear = "<1y"
  case overYear = "1y+"
  case existing
}
