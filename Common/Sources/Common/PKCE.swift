import CryptoKit
import Foundation

/// Proof Key for Code Exchange (PKCE) implementation for OAuth 2.0
///
/// PKCE is an extension to the OAuth 2.0 Authorization Code flow to prevent CSRF
/// and authorization code injection attacks. It uses a code verifier and challenge
/// to ensure that the authorization code can only be exchanged by the client that
/// initiated the authorization request.
///
/// Reference: [RFC 7636](https://tools.ietf.org/html/rfc7636)
public struct PKCE: Sendable {
  /// The code verifier - a cryptographically random string
  public let verifier: String

  /// The code challenge - a SHA256 hash of the verifier, base64url encoded
  public let challenge: String

  /// Creates a new PKCE instance with a randomly generated verifier and corresponding challenge
  public init() {
    verifier = PKCE.randomBase64URL(length: 48)
    challenge = PKCE.sha256Base64URL(verifier)
  }

  /// Generates a cryptographically random base64url-encoded string
  ///
  /// - Parameter length: The number of random bytes to generate
  /// - Returns: A base64url-encoded string
  private static func randomBase64URL(length: Int) -> String {
    let bytes = (0..<length).map { _ in UInt8.random(in: 0...255) }
    return Data(bytes).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  /// Creates a SHA256 hash of the input and returns it as a base64url-encoded string
  ///
  /// - Parameter input: The string to hash
  /// - Returns: A base64url-encoded SHA256 hash
  private static func sha256Base64URL(_ input: String) -> String {
    let hash = SHA256.hash(data: Data(input.utf8))
    return Data(hash).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }
}
