import Foundation

/// Multicast `AsyncStream` fan-out.
///
/// Each call to ``subscribe()`` returns a fresh stream that receives every
/// subsequent ``emit(_:)`` value. When a consumer cancels its task the
/// associated continuation is unregistered automatically.
///
/// Same shape as Combine's `PassthroughSubject` (drop-on-floor for late
/// subscribers, no replay), but consumed as an `AsyncSequence`. Used here to
/// observe GRDB table changes; will also back the `CacheChange` signal in
/// later stages of the offline-cache plan and the event-bus migration on
/// `DocumentStore` / `ConnectionManager`.
public final class Broadcaster<Element: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

  public init() {}

  /// Returns a fresh stream. The stream finishes when the broadcaster is
  /// deallocated, when ``finishAll()`` is called, or when the consuming task
  /// is cancelled.
  public func subscribe() -> AsyncStream<Element> {
    let id = UUID()
    return AsyncStream { continuation in
      lock.withLock { continuations[id] = continuation }
      continuation.onTermination = { [weak self] _ in
        guard let self else { return }
        lock.withLock { _ = continuations.removeValue(forKey: id) }
      }
    }
  }

  public func emit(_ element: Element) {
    let snapshot = lock.withLock { Array(continuations.values) }
    for continuation in snapshot {
      continuation.yield(element)
    }
  }

  public func finishAll() {
    let snapshot = lock.withLock { () -> [AsyncStream<Element>.Continuation] in
      let values = Array(continuations.values)
      continuations.removeAll()
      return values
    }
    for continuation in snapshot {
      continuation.finish()
    }
  }

  deinit {
    finishAll()
  }
}
