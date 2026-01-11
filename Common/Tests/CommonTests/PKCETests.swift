//
//  PKCETests.swift
//  Common
//
//  Created by Claude Code
//

import CryptoKit
import Foundation
import Testing

@testable import Common

@Suite
struct PKCETests {
  @Test
  func generatesValidPKCEInstance() {
    let pkce = PKCE()

    // Verifier and challenge should exist and not be empty
    #expect(!pkce.verifier.isEmpty)
    #expect(!pkce.challenge.isEmpty)

    // Should have valid base64url format (no +, /, or =)
    #expect(!pkce.verifier.contains("+"))
    #expect(!pkce.verifier.contains("/"))
    #expect(!pkce.verifier.contains("="))
    #expect(!pkce.challenge.contains("+"))
    #expect(!pkce.challenge.contains("/"))
    #expect(!pkce.challenge.contains("="))

    // Verifier and challenge should be different
    #expect(pkce.verifier != pkce.challenge)

    // Challenge should be exactly 43 characters (SHA256 base64url encoded)
    #expect(pkce.challenge.count == 43)
  }

  @Test
  func challengeIsSHA256OfVerifier() {
    let pkce = PKCE()

    // Verify challenge matches direct CryptoKit computation
    let hash = SHA256.hash(data: Data(pkce.verifier.utf8))
    let expectedChallenge = Data(hash).base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
    #expect(pkce.challenge == expectedChallenge)
  }

  @Test
  func eachInstanceHasUniqueValues() {
    let pkce1 = PKCE()
    let pkce2 = PKCE()
    let pkce3 = PKCE()

    // Different instances should have different verifiers
    #expect(pkce1.verifier != pkce2.verifier)
    #expect(pkce2.verifier != pkce3.verifier)
    #expect(pkce1.verifier != pkce3.verifier)

    // Different instances should have different challenges
    #expect(pkce1.challenge != pkce2.challenge)
    #expect(pkce2.challenge != pkce3.challenge)
    #expect(pkce1.challenge != pkce3.challenge)
  }
}
