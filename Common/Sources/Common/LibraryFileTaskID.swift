//
//  LibraryFileTaskID.swift
//  Common
//
//  The description a library file download task carries, and its parse back
//  into what the delegate needs to file and record the download.
//

import Foundation

/// A background download task outlives the process that created it, so its
/// `taskDescription` carries everything the delegate needs: the store key,
/// the document, and the `modified` the file was fetched against.
public enum LibraryFileTaskID {
  private static let prefix = "swift-paperless:file/"

  public static func make(key: ContentStore.Key, documentID: UInt, modified: Date) -> String {
    "\(prefix)\(key.serverID.uuidString)/\(documentID)/\(key.versionID)/\(key.kind.rawValue)/\(modified.timeIntervalSinceReferenceDate)"
  }

  public static func parse(_ id: String)
    -> (key: ContentStore.Key, documentID: UInt, modified: Date)?
  {
    guard id.hasPrefix(prefix) else { return nil }
    let parts = id.dropFirst(prefix.count).split(separator: "/", omittingEmptySubsequences: false)
    guard parts.count == 5,
      let serverID = UUID(uuidString: String(parts[0])),
      let documentID = UInt(parts[1]),
      let versionID = UInt(parts[2]),
      let kind = ContentStore.Kind(rawValue: String(parts[3])),
      let modified = TimeInterval(parts[4])
    else { return nil }
    return (
      ContentStore.Key(serverID: serverID, versionID: versionID, kind: kind), documentID,
      Date(timeIntervalSinceReferenceDate: modified)
    )
  }
}
