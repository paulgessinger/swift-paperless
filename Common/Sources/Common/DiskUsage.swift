//
//  DiskUsage.swift
//  Common
//

import Foundation

/// How much disk a set of files occupies, for the storage statistics on the
/// Offline & Sync screen.
///
/// Measured with a synchronous directory walk, so callers must keep it off the
/// main actor: the blob store alone can hold thousands of version directories.
public struct DiskUsage: Sendable, Equatable {
  /// Bytes the files occupy on disk.
  ///
  /// Allocated size rather than logical length where the file system reports
  /// it: that is what the user gets back by deleting the files, and it is the
  /// figure iOS's own storage screen shows. The two differ by block rounding,
  /// which adds up across thousands of small sidecars and thumbnails.
  public var bytes: Int64
  /// Regular files counted, directories excluded.
  public var files: Int

  public init(bytes: Int64 = 0, files: Int = 0) {
    self.bytes = bytes
    self.files = files
  }

  public static let zero = DiskUsage()

  public static func + (lhs: DiskUsage, rhs: DiskUsage) -> DiskUsage {
    DiskUsage(bytes: lhs.bytes + rhs.bytes, files: lhs.files + rhs.files)
  }

  public static func += (lhs: inout DiskUsage, rhs: DiskUsage) {
    lhs = lhs + rhs
  }

  private static let resourceKeys: Set<URLResourceKey> = [
    .isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey,
  ]

  /// Usage of `url`: a single file, or everything beneath a directory.
  ///
  /// A path that doesn't exist measures as zero rather than throwing — a cache
  /// nothing has written to yet (or that a wipe just removed) is empty, not an
  /// error — and so does anything the walk can't read, for the same reason:
  /// these figures are informational, and a partial answer beats none.
  ///
  /// - Parameter counting: which regular files add to ``files``. Every file
  ///   adds to ``bytes`` regardless, so a caller can count only the files a
  ///   user would recognise (a downloaded PDF, not its metadata sidecar)
  ///   without under-reporting the space.
  public static func measure(
    _ url: URL, counting: (URL) -> Bool = { _ in true }
  ) -> DiskUsage {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
      return .zero
    }
    guard isDirectory.boolValue else {
      return measureFile(url, counting: counting)
    }

    // No `.skipsHiddenFiles`: dotfiles (e.g. a Nuke or GRDB temp file) take up
    // space like any other, and leaving them out would under-report.
    guard
      let enumerator = FileManager.default.enumerator(
        at: url, includingPropertiesForKeys: Array(resourceKeys), options: [],
        errorHandler: { _, _ in true })
    else { return .zero }

    var usage = DiskUsage.zero
    for case let file as URL in enumerator {
      usage += measureFile(file, counting: counting)
    }
    return usage
  }

  /// Sum of ``measure(_:)`` over `urls`, e.g. a SQLite file and its sidecars.
  public static func measure(_ urls: [URL]) -> DiskUsage {
    urls.reduce(into: .zero) { $0 += measure($1) }
  }

  private static func measureFile(_ url: URL, counting: (URL) -> Bool) -> DiskUsage {
    guard let values = try? url.resourceValues(forKeys: resourceKeys),
      values.isRegularFile == true
    else { return .zero }
    let bytes = values.totalFileAllocatedSize ?? values.fileSize ?? 0
    return DiskUsage(bytes: Int64(bytes), files: counting(url) ? 1 : 0)
  }
}
