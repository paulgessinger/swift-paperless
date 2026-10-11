//
//  StoragePolicy.swift
//  Common
//
//  The limits that bound what the offline data takes on disk and how the
//  sweep that enforces them behaves, in one place; where each applies is
//  documented at the use.
//

import Foundation

public enum StoragePolicy {
  /// What the evictable document files (originals and archives) may take in
  /// total across servers; past it the least recently accessed go first.
  public static let documentBudgetBytes: Int64 = 500_000_000

  /// The resized thumbnails the image pipeline derives, a plain
  /// least-recently-used cache next to the content store.
  public static let thumbnailVariantCacheBytes = 150 * 1024 * 1024

  /// A file accessed inside this window is never evicted, so a pass does not
  /// unlink a file that is on screen.
  public static let recentAccessGrace: TimeInterval = 300

  /// A file without an index row is left alone this long: a download exists
  /// on disk before the row that records it, and the Share Extension may be
  /// mid-write while the app sweeps. An hour is orders of magnitude longer
  /// than that window.
  public static let unindexedFileGrace: TimeInterval = 3600

  /// How often the sweep may run behind a reconcile.
  public static let sweepInterval: TimeInterval = 3600

  /// Accesses to one file inside this window are recorded once, so a hit
  /// never costs a write per tap.
  public static let accessCoalescing: TimeInterval = 60
}
