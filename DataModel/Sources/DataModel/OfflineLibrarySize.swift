//
//  OfflineLibrarySize.swift
//  DataModel
//

import Foundation

/// Pure decision logic behind the size-adaptive default for
/// `AppShared.OfflineBrowsingMode`. Lives here (not in `AppShared`, which has
/// no test target of its own) so the comparison gets a real unit test.
public enum OfflineLibrarySize {
  /// Document-count threshold below which a newly connected server defaults
  /// to proactively caching the entire library.
  public static let entireLibraryThreshold: UInt = 2_000

  /// `nil` (the count probe failed or was never attempted) is always treated
  /// as "not small" — the conservative fallback.
  public static func isSmall(documentCount count: UInt?) -> Bool {
    guard let count else { return false }
    return count < entireLibraryThreshold
  }

  /// How many of the default list's cached rows survive a `.entireLibrary` →
  /// `.recentlyBrowsed` downgrade. Deliberately much smaller than
  /// `entireLibraryThreshold` — that number answers "is this library small
  /// enough to go greedy by default," this one answers "how light should
  /// `.recentlyBrowsed` stay."
  public static let recentlyBrowsedDefaultListCap = 200
}
