//
//  ScannerDiscoveryMergeTest.swift
//  Scanning
//

import Foundation
import Testing

@testable import Scanning

private func ref(
  _ id: String, host: String = "192.168.1.10", port: Int?, root: String = "eSCL",
  plainText: Bool, model: String? = nil
) -> ScannerRef {
  ScannerRef(
    id: id, hostname: host, port: port, root: root, usePlainText: plainText, model: model)
}

@Suite @MainActor
struct ScannerDiscoveryMergeTest {
  @Test func prefersTheSecureTransport() {
    let plain = ref("uuid-1", port: 80, root: "eSCL", plainText: true)
    let secure = ref("uuid-1", port: 443, root: "eSCL/secure", plainText: false)

    let merged = ScannerDiscovery.merge(secure: [secure], plain: [plain])

    #expect(merged.count == 1)
    #expect(merged[0].usePlainText == false)
  }

  /// The transports advertise a different port *and* a different root, so a
  /// record must be replaced whole — a mixture addresses a scanner that is not
  /// there.
  @Test func replacesWholeRecordsRatherThanMerging() {
    let plain = ref("uuid-1", port: 80, root: "eSCL", plainText: true, model: "Plain Name")
    let secure = ref("uuid-1", port: 8443, root: "airscan/eSCL", plainText: false)

    let merged = ScannerDiscovery.merge(secure: [secure], plain: [plain])

    #expect(merged[0].port == 8443)
    #expect(merged[0].root == "airscan/eSCL")
    // Not back-filled from the insecure record.
    #expect(merged[0].model == nil)
  }

  @Test func keepsScannersOnlyOneTransportSaw() {
    let plain = ref("only-plain", port: 80, plainText: true)
    let secure = ref("only-secure", port: 443, plainText: false)

    let merged = ScannerDiscovery.merge(secure: [secure], plain: [plain])

    #expect(Set(merged.map(\.id)) == ["only-plain", "only-secure"])
  }

  @Test func ordersDeterministically() {
    let a = ref("uuid-a", port: 443, plainText: false, model: "Alpha")
    let b = ref("uuid-b", port: 443, plainText: false, model: "beta")
    let c = ref("uuid-c", port: 443, plainText: false, model: "Gamma")

    let forwards = ScannerDiscovery.merge(secure: [a, b, c], plain: [])
    let backwards = ScannerDiscovery.merge(secure: [c, b, a], plain: [])

    #expect(forwards.map(\.id) == ["uuid-a", "uuid-b", "uuid-c"])
    #expect(forwards == backwards)
  }

  @Test func breaksNameTiesByIdentifier() {
    let first = ref("uuid-b", port: 443, plainText: false, model: "Same")
    let second = ref("uuid-a", port: 443, plainText: false, model: "Same")

    let merged = ScannerDiscovery.merge(secure: [first, second], plain: [])

    #expect(merged.map(\.id) == ["uuid-a", "uuid-b"])
  }

  @Test func fallsBackToHostnameWhenTheScannerHasNoModel() {
    #expect(
      ref("uuid-1", host: "scanner.local", port: nil, plainText: false).displayName
        == "scanner.local")
  }
}
