//
//  FetchFaviconTests.swift
//  Common
//
//  Created by Claude Code
//

import Foundation
import Testing

@testable import Common

@Suite
struct FetchFaviconTests {
  @Test
  func fetchGitHubFavicon() async throws {
    let url = URL(string: "https://github.com/")!
    let iconURL = await fetchFavicon(from: url)

    // GitHub should have a favicon
    #expect(iconURL != nil, "Failed to fetch favicon from GitHub")

    // The icon URL should be valid and contain "favicon" or "icon"
    if let iconURL {
      #expect(iconURL.absoluteString.contains("favicon") || iconURL.absoluteString.contains("icon"))
    }
  }

  @Test
  func testInvalidURL() async throws {
    // Verify the function returns nil for non-existent domains
    let invalidURL = URL(string: "https://this-does-not-exist-test-12345.com/")!
    let result = await fetchFavicon(from: invalidURL)
    #expect(result == nil, "Should return nil for non-existent domains")
  }
}
