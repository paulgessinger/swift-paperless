//
//  NamedFileLink.swift
//  AppShared
//

import Foundation

/// A stored document file under the name a user would recognise. Canonical
/// store paths don't say what a file is, and the share sheet, Files and
/// QuickLook all go by the name's extension.
public enum NamedFileLink {
  /// Hardlinks `canonical` as `name` into a fresh subdirectory of
  /// `NSTemporaryDirectory()`, or returns `nil` when that fails.
  ///
  /// The link shares an inode with the canonical blob, so there is no data
  /// copy, and it keeps the bytes it was made from when the store later
  /// replaces the file by rename. The fresh subdirectory means no collision
  /// logic; the OS purges `NSTemporaryDirectory()`, so no cleanup is needed.
  public static func stage(_ canonical: URL, as name: String) -> URL? {
    do {
      let subdir = FileManager.default.temporaryDirectory
        .appendingPathComponent("Share-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: subdir, withIntermediateDirectories: true)
      let dest = subdir.appendingPathComponent(sanitize(name))
      try FileManager.default.linkItem(at: canonical, to: dest)
      return dest
    } catch {
      return nil
    }
  }

  static func sanitize(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\0").union(.controlCharacters)
    let scrubbed = name.components(separatedBy: invalid).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return scrubbed.isEmpty ? "document" : scrubbed
  }
}
