//
//  FileIndex.swift
//  Common
//
//  What the download path needs from the index of cached files. The index
//  itself is a database table in Persistence; Networking only sees this.
//

import Foundation

/// One indexed file, as the download path reads it.
public struct FileIndexEntry: Sendable, Equatable {
  public let key: ContentStore.Key
  public let documentID: UInt
  public let size: Int64
  /// The document's `modified` the file was fetched against.
  public let modified: Date?
  public let storedAt: Date
  public let lastAccessedAt: Date?

  public init(
    key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, storedAt: Date,
    lastAccessedAt: Date?
  ) {
    self.key = key
    self.documentID = documentID
    self.size = size
    self.modified = modified
    self.storedAt = storedAt
    self.lastAccessedAt = lastAccessedAt
  }
}

/// The index of the files a ``ContentStore`` holds. A file is written to the
/// store first and recorded here second, so a row always has a file behind it
/// unless the file was removed from under it, which the repair walk corrects.
public protocol FileIndex: Sendable {
  /// The entry for `key` if its file was fetched against exactly `modified`.
  func freshEntry(for key: ContentStore.Key, modified: Date) async throws -> FileIndexEntry?

  /// Record the file now at `key`, replacing any earlier entry.
  func recordStore(
    _ key: ContentStore.Key, documentID: UInt, size: Int64, modified: Date?, checksum: String?,
    storedAt: Date
  ) async throws

  /// Note that the file at `key` was served, for the storage budget's
  /// least-recently-used order.
  func recordAccess(_ key: ContentStore.Key, at date: Date) async throws

  /// Drop the entry for `key`, whose file the caller has removed.
  func forget(_ key: ContentStore.Key) async throws
}
