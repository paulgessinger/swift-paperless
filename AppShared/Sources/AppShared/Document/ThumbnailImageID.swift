//
//  ThumbnailImageID.swift
//  AppShared
//
//  The one definition of the Nuke `imageId` a thumbnail request carries, and
//  its parse back into the content store key the thumbnail is filed under.
//

import Common
import DataModel
import Foundation

/// Thumbnails are keyed by server and version, not by request URL: the disk
/// cache behind the image pipeline is the content store's `thumbnail.bin` for
/// that version, which is also what the file index records.
///
/// Nuke keys a resized variant by the id plus the processors' identifiers, so
/// a key is one of three things: an exact id, an id with a suffix, or foreign.
public enum ThumbnailImageID {
  private static let prefix = "swift-paperless:thumbnail/"

  public static func make(serverID: UUID, document: Document) -> String {
    "\(prefix)\(serverID.uuidString)/\(document.id)/\(document.currentVersionID)"
  }

  /// Strict: nothing but an exact id maps to a file.
  public static func parse(_ id: String) -> (key: ContentStore.Key, documentID: UInt)? {
    guard let (parsed, suffix) = split(id), suffix.isEmpty else { return nil }
    return parsed
  }

  /// Whether `key` is an id followed by a processor suffix: the key Nuke
  /// stores a resized variant under.
  public static func isVariant(_ key: String) -> Bool {
    guard let (_, suffix) = split(key) else { return false }
    return !suffix.isEmpty
  }

  /// The id at the start of `key` and whatever follows the version's digits.
  private static func split(_ key: String)
    -> (parsed: (key: ContentStore.Key, documentID: UInt), suffix: Substring)?
  {
    guard key.hasPrefix(prefix) else { return nil }
    let parts = key.dropFirst(prefix.count)
      .split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 3,
      let serverID = UUID(uuidString: String(parts[0])),
      let documentID = UInt(parts[1])
    else { return nil }
    let digits = parts[2].prefix { $0.isASCII && $0.isNumber }
    guard let versionID = UInt(digits) else { return nil }
    let key = ContentStore.Key(serverID: serverID, versionID: versionID, kind: .thumbnail)
    return ((key, documentID), parts[2].dropFirst(digits.count))
  }
}
