//
//  ScannerRef.swift
//  Scanning
//

import Foundation

/// Everything needed to reach one eSCL scanner, as a value.
///
/// SwiftESCL's own `EsclScanner` is a non-`Sendable` class with mutable state,
/// so it must never leave the isolation domain it was created in. This is what
/// crosses instead: discovery produces it on the main actor, and
/// ``ScannerClient`` rebuilds a throwaway `EsclScanner` from it inside the
/// concurrent scan.
///
/// The capability-ish fields a scanner advertises over Bonjour (mime types,
/// colour spaces, input sources) are deliberately absent. They are non-`Sendable`
/// SwiftESCL types, the scan path never reads them, and
/// ``ScannerClient/capabilities(of:)`` is the authoritative source anyway.
public struct ScannerRef: Sendable, Identifiable, Hashable {
  /// The `uuid` from the Bonjour TXT record. Stable across both transports,
  /// which is what makes it usable as the merge key in ``ScannerDiscovery``.
  public let id: String
  public let hostname: String
  public let port: Int?
  /// The `rs` TXT value — the eSCL root path, usually `eSCL`. Advertised
  /// separately per transport, so it travels with the host and port.
  public let root: String
  /// `true` for `_uscan._tcp` (HTTP), `false` for `_uscans._tcp` (HTTPS).
  public let usePlainText: Bool
  public let model: String?
  public let location: String?
  public let esclVersion: String?

  public init(
    id: String,
    hostname: String,
    port: Int?,
    root: String,
    usePlainText: Bool,
    model: String? = nil,
    location: String? = nil,
    esclVersion: String? = nil
  ) {
    self.id = id
    self.hostname = hostname
    self.port = port
    self.root = root
    self.usePlainText = usePlainText
    self.model = model
    self.location = location
    self.esclVersion = esclVersion
  }

  /// What to show in a scanner list.
  public var displayName: String {
    model ?? hostname
  }
}
