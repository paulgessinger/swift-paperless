import Foundation
import os

/// A position in the document deletion log, captured by a writer before it
/// issues its request and handed to its write.
public struct DocumentDeletionMark: Sendable, Equatable {
  let sequence: UInt64
}

/// What a list write is based on, captured before its request.
public struct QueryWriteBasis: Sendable, Equatable {
  /// The key's mark counter, which the written order accounts for.
  public let generation: QueryOrderGeneration
  /// Ids deleted after this point are kept out of the write.
  public let deletions: DocumentDeletionMark
}

/// The documents deleted from the cache recently, in memory, so that a write
/// carrying a server answer computed before a delete can leave the deleted
/// documents out instead of bringing them back.
///
/// One per ``Database``, so one per process: a delete committed by another
/// process sharing the file is not recorded here.
///
/// Bounded at ``capacity`` entries. A mark from before an evicted entry can't
/// be checked completely; ``deleted(since:serverID:)`` says so and the writer
/// falls back to leaving the list order-stale.
final class DocumentDeletionLog: Sendable {
  /// The log only has to cover deletes made while a request is in flight
  /// (seconds; a full library fill, minutes), which local deletes don't come
  /// close to. A remote-delete reconcile pruning more ids than this at once
  /// trips the fallback for the writes in flight across it.
  static let defaultCapacity = 10_000

  /// The ids deleted after a mark, for one server.
  struct Deleted: Equatable {
    var ids: Set<UInt>
    /// `false` if entries after the mark were evicted, so `ids` may be missing
    /// some deletions.
    var isComplete: Bool
  }

  private struct Key: Hashable, Sendable {
    var serverID: UUID
    var id: UInt
  }

  private struct Entry: Sendable {
    var sequence: UInt64
    var serverID: UUID
    var id: UInt

    var key: Key { Key(serverID: serverID, id: id) }
  }

  private struct State: Sendable {
    /// One sequence for every server, so a mark never meets a reused number
    /// after a server's entries are dropped.
    var sequence: UInt64 = 0
    /// The newest sequence that had an entry evicted; marks before it can't be
    /// checked completely.
    var evictedThrough: UInt64 = 0
    /// Oldest first, including entries a later deletion of the same id
    /// superseded in `latest`: a rollback of that later one falls back to them.
    var entries: [Entry] = []
    /// The sequence each id was last deleted at.
    var latest: [UUID: [UInt: UInt64]] = [:]
  }

  let capacity: Int
  private let state = OSAllocatedUnfairLock(initialState: State())

  init(capacity: Int = defaultCapacity) {
    self.capacity = capacity
  }

  func mark() -> DocumentDeletionMark {
    DocumentDeletionMark(sequence: state.withLock { $0.sequence })
  }

  /// Record a deletion of `ids` and return its sequence.
  @discardableResult
  func record(_ ids: [UInt], serverID: UUID) -> UInt64 {
    let capacity = capacity
    return state.withLock { state in
      state.sequence += 1
      let sequence = state.sequence
      for id in ids {
        state.entries.append(Entry(sequence: sequence, serverID: serverID, id: id))
        state.latest[serverID, default: [:]][id] = sequence
      }
      let overflow = state.entries.count - capacity
      if overflow > 0 {
        for entry in state.entries.prefix(overflow) {
          if state.latest[entry.serverID]?[entry.id] == entry.sequence {
            state.latest[entry.serverID]?[entry.id] = nil
          }
          state.evictedThrough = max(state.evictedThrough, entry.sequence)
        }
        state.entries.removeFirst(overflow)
      }
      return sequence
    }
  }

  /// Undo ``record(_:serverID:)`` for a deletion whose transaction rolled back,
  /// falling back to each id's earlier retained deletion. An eviction it caused
  /// stays: that only makes older marks fall back.
  func discard(sequence: UInt64) {
    state.withLock { state in
      let discarded = state.entries.filter { $0.sequence == sequence }
      guard !discarded.isEmpty else { return }
      state.entries.removeAll { $0.sequence == sequence }
      for entry in discarded where state.latest[entry.serverID]?[entry.id] == sequence {
        state.latest[entry.serverID]?[entry.id] = nil
      }
      let affected = Set(discarded.map(\.key))
      for entry in state.entries where affected.contains(entry.key) {
        state.latest[entry.serverID, default: [:]][entry.id] = entry.sequence
      }
    }
  }

  /// Stop excluding `ids`, which exist again (restored from the trash).
  func forget(_ ids: [UInt], serverID: UUID) {
    let ids = Set(ids)
    state.withLock { state in
      for id in ids {
        state.latest[serverID]?[id] = nil
      }
      state.entries.removeAll { $0.serverID == serverID && ids.contains($0.id) }
    }
  }

  /// Drop every entry for a server that no longer exists.
  func drop(serverID: UUID) {
    state.withLock { state in
      state.latest[serverID] = nil
      state.entries.removeAll { $0.serverID == serverID }
    }
  }

  func deleted(since mark: DocumentDeletionMark, serverID: UUID) -> Deleted {
    state.withLock { state in
      let ids = (state.latest[serverID] ?? [:]).filter { $0.value > mark.sequence }.keys
      return Deleted(ids: Set(ids), isComplete: mark.sequence >= state.evictedThrough)
    }
  }
}
