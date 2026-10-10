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
public enum ThumbnailImageID {
  private static let prefix = "swift-paperless:thumbnail/"

  public static func make(serverID: UUID, document: Document) -> String {
    "\(prefix)\(serverID.uuidString)/\(document.id)/\(document.currentVersionID)"
  }

  /// Strict: Nuke also probes its data cache with the id plus a processor
  /// suffix, and nothing but an exact id maps to a file.
  public static func parse(_ id: String) -> (key: ContentStore.Key, documentID: UInt)? {
    guard id.hasPrefix(prefix) else { return nil }
    let parts = id.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 3,
      let serverID = UUID(uuidString: String(parts[0])),
      let documentID = UInt(parts[1]),
      let versionID = UInt(parts[2])
    else { return nil }
    return (
      ContentStore.Key(serverID: serverID, versionID: versionID, kind: .thumbnail), documentID
    )
  }
}
