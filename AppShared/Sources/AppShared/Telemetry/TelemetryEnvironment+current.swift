//
//  TelemetryEnvironment+current.swift
//  AppShared
//

#if os(iOS)
  import Foundation
  import Networking
  import UIKit

  extension TelemetryEnvironment {
    /// The environment of this install and its active server.
    @MainActor
    public static func current(
      store: DocumentStore, connectionManager: ConnectionManager
    ) async -> TelemetryEnvironment {
      let os = ProcessInfo.processInfo.operatingSystemVersion
      let active = connectionManager.storedConnection
      let versions = active?.knownVersions

      return TelemetryEnvironment(
        channel: TelemetryChannel(Bundle.main.appConfiguration),
        appVersion: Bundle.main.releaseVersionNumber ?? "other",
        osMajor: os.majorVersion,
        osMinor: os.minorVersion,
        device: UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone,
        localization: Bundle.main.preferredLocalizations.first ?? "en",
        backendVersion: versions.map { $0.backendVersion.description },
        apiVersion: versions.map { min(ApiRepository.maximumApiVersion, $0.apiVersion) },
        documentCount: await store.libraryDocumentCount(),
        auth: active?.authMethod,
        clientCertificate: active?.identity != nil,
        customHeaders: !(active?.extraHeaders.isEmpty ?? true),
        serverCount: connectionManager.connections.count,
        availableFeatures: TelemetryFeature.allCases)
    }
  }
#endif
