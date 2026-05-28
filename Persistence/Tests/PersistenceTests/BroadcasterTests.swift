import Testing

@testable import Persistence

@Suite("Broadcaster")
struct BroadcasterTests {
  @Test("multiple subscribers each receive every emit")
  func multipleSubscribersReceiveEmits() async throws {
    let broadcaster = Broadcaster<Int>()
    let s1 = broadcaster.subscribe()
    let s2 = broadcaster.subscribe()

    async let collected1: [Int] = collect(s1, count: 3)
    async let collected2: [Int] = collect(s2, count: 3)

    // Give the subscribers a moment to attach before emitting.
    try await Task.sleep(for: .milliseconds(10))
    broadcaster.emit(1)
    broadcaster.emit(2)
    broadcaster.emit(3)

    let r1 = await collected1
    let r2 = await collected2
    #expect(r1 == [1, 2, 3])
    #expect(r2 == [1, 2, 3])
  }

  @Test("emit before subscribe is dropped")
  func emitBeforeSubscribeIsDropped() async throws {
    let broadcaster = Broadcaster<Int>()
    broadcaster.emit(1)  // no subscribers yet → dropped
    let stream = broadcaster.subscribe()
    async let collected: [Int] = collect(stream, count: 1)
    try await Task.sleep(for: .milliseconds(10))
    broadcaster.emit(2)
    let result = await collected
    #expect(result == [2])
  }

  @Test("cancelling a consumer unregisters its continuation")
  func cancellationUnregistersContinuation() async throws {
    let broadcaster = Broadcaster<Int>()
    let stream = broadcaster.subscribe()
    let task = Task<Void, Never> {
      for await _ in stream {
        // consume until cancelled
      }
    }
    try await Task.sleep(for: .milliseconds(10))
    task.cancel()
    // After cancellation propagates, subsequent emits must not crash and the
    // map must drain. There is no public count accessor, so we just confirm
    // the broadcaster is still usable.
    try await Task.sleep(for: .milliseconds(20))
    broadcaster.emit(42)
    broadcaster.finishAll()
  }

  @Test("finishAll terminates open streams")
  func finishAllTerminatesStreams() async throws {
    let broadcaster = Broadcaster<Int>()
    let stream = broadcaster.subscribe()

    async let drained: [Int] = collectAll(stream)
    try await Task.sleep(for: .milliseconds(10))
    broadcaster.emit(1)
    broadcaster.emit(2)
    broadcaster.finishAll()

    let result = await drained
    #expect(result == [1, 2])
  }

  // MARK: - Helpers

  private func collect<S: AsyncSequence>(_ sequence: S, count: Int) async -> [S.Element]
  where S.Element: Sendable, S: Sendable {
    var values: [S.Element] = []
    do {
      for try await value in sequence {
        values.append(value)
        if values.count == count { break }
      }
    } catch {
      // Asynstream never throws but the protocol allows it; ignore.
    }
    return values
  }

  private func collectAll<S: AsyncSequence>(_ sequence: S) async -> [S.Element]
  where S.Element: Sendable, S: Sendable {
    var values: [S.Element] = []
    do {
      for try await value in sequence {
        values.append(value)
      }
    } catch {
      // AsyncStream never throws.
    }
    return values
  }
}
