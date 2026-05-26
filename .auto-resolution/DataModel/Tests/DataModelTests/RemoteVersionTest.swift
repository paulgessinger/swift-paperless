import Common
import Foundation
import Testing

@testable import DataModel

@Test("Remote version can be decoded from JSON")
func testDecodeRemoteVersion() throws {
  let json = """
    {"version":"v2.20.5","update_available":true}
    """.data(using: .utf8)!

  let decoder = JSONDecoder()
  let remoteVersion = try decoder.decode(RemoteVersion.self, from: json)

  #expect(remoteVersion.version == Version(2, 20, 5))
  #expect(remoteVersion.updateAvailable == true)
}
