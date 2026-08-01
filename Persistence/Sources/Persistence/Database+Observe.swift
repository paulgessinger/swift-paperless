import DataModel
import Foundation
import GRDB

/// Typed live queries over the element cache — the source-of-truth read path.
///
/// Like ``Database/observeConnections()``, each method wraps GRDB
/// `ValueObservation` and surfaces it as an `AsyncThrowingStream` of **domain**
/// values: GRDB, `ValueObservation`, and SQL never cross the `Persistence`
/// boundary. The first element is the current state (so a consumer's
/// `for try await` loop is "initial hydrate + live updates" in one), exactly
/// like the connection observer.
///
/// Each emission carries the freshly-mapped domain result, so a consumer
/// assigns it directly and never re-reads the database to find out what
/// changed.
///
/// Scope: the observation tracks the whole table region, so a write to
/// *another* server's rows re-fires this stream with an identical array. That
/// is harmless while one server is active and not worth narrowing.
extension Database {
  /// Live, name-ordered list of one element collection for a server.
  public func observeElements<R: ElementRecord>(
    _ type: R.Type, serverID: UUID
  ) -> AsyncThrowingStream<[R.Domain], Error> {
    let observation = ValueObservation.tracking { db in
      try R
        .filter(Column("server_id") == serverID)
        .order(Column("name"))
        .fetchAll(db)
        .map(\.domain)
    }
    return stream(observation)
  }

  /// Live per-server `UISettings` singleton (`nil` until first cached/synced).
  public func observeUISettings(serverID: UUID) -> AsyncThrowingStream<UISettings?, Error> {
    let observation = ValueObservation.tracking { db in
      try UISettingsRecord.fetchOne(db, key: serverID)?.domain
    }
    return stream(observation)
  }

  /// Live per-server `ServerConfiguration` singleton (`nil` until cached/synced).
  public func observeServerConfiguration(
    serverID: UUID
  ) -> AsyncThrowingStream<ServerConfiguration?, Error> {
    let observation = ValueObservation.tracking { db in
      try ServerConfigurationRecord.fetchOne(db, key: serverID)?.domain
    }
    return stream(observation)
  }

  /// Shared adapter: drive a `ValueObservation` into an `AsyncThrowingStream`,
  /// mirroring ``observeConnections()``. Cancelling the consuming task tears
  /// down the underlying observation.
  private func stream<Value: Sendable>(
    _ observation: ValueObservation<ValueReducers.Fetch<Value>>
  ) -> AsyncThrowingStream<Value, Error> {
    let writer = writer
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for try await value in observation.values(in: writer) {
            continuation.yield(value)
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
