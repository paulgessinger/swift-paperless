import Foundation
import Security
import Testing

@testable import Common

// The attribute dictionaries only: SecItem calls on a macOS host go to the
// login keychain, not the data-protection keychain the app uses.
@Suite
struct KeychainAttributesTests {
  @Test("a saved token is readable after first unlock")
  func saveSetsAccessibility() {
    let attributes = Keychain.saveAttributes(service: "s", account: "a", value: Data())
    #expect(
      attributes[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleAfterFirstUnlock)
  }

  @Test("updating a token also moves it to after-first-unlock")
  func updateSetsAccessibility() {
    let attributes = Keychain.updateAttributes(value: Data())
    #expect(
      attributes[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleAfterFirstUnlock)
  }
}
