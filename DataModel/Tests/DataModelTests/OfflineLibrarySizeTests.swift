//
//  OfflineLibrarySizeTests.swift
//  DataModel
//

import Testing

@testable import DataModel

@Suite
struct OfflineLibrarySizeTests {
  @Test
  func nilCountIsNotSmall() {
    #expect(!OfflineLibrarySize.isSmall(documentCount: nil))
  }

  @Test
  func belowThresholdIsSmall() {
    #expect(
      OfflineLibrarySize.isSmall(documentCount: OfflineLibrarySize.entireLibraryThreshold - 1))
  }

  @Test
  func atThresholdIsNotSmall() {
    #expect(!OfflineLibrarySize.isSmall(documentCount: OfflineLibrarySize.entireLibraryThreshold))
  }

  @Test
  func aboveThresholdIsNotSmall() {
    #expect(
      !OfflineLibrarySize.isSmall(documentCount: OfflineLibrarySize.entireLibraryThreshold + 1))
  }
}
