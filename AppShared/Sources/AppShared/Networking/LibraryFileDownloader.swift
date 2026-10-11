//
//  LibraryFileDownloader.swift
//  AppShared
//
//  The library's document files, downloaded ahead of time on one background
//  `URLSession`, so the transfers go on while the app is suspended and the
//  app is relaunched to file what finished.
//

import Common
import DataModel
import Foundation
import Networking
import Persistence
import os

/// What the downloader needs to know about a server to queue its files.
public struct LibraryDownloadServer: Sendable {
  /// Whether its downloads may use cellular data; Low Data Mode always stops
  /// them.
  public let syncOverCellular: Bool
  /// Whether every document is downloaded, or only the ones kept offline.
  public let isEntireLibrary: Bool
  /// Builds the authenticated requests. Only a refill with something to
  /// queue asks for it: preparing it can build the server's stack.
  public let repository: @MainActor @Sendable () async throws -> any Repository

  public init(
    syncOverCellular: Bool, isEntireLibrary: Bool,
    repository: @escaping @MainActor @Sendable () async throws -> any Repository
  ) {
    self.syncOverCellular = syncOverCellular
    self.isEntireLibrary = isEntireLibrary
    self.repository = repository
  }

  var scope: LibraryFileScope { isEntireLibrary ? .library : .keptOffline }
}

/// Keeps a window of archive downloads in flight per server: the whole
/// library of an *Entire library* server, the documents kept offline of any
/// other. The index is the source of truth for what is missing: a refill
/// asks the database for the newest documents in that scope whose archive is
/// missing or outdated, leaves out the ones in flight, and hands iOS the
/// rest, up to the window.
///
/// Everything happens as events through one loop on the main actor, in the
/// order they arrive: the session's completions, from its serial delegate
/// queue, and the refills and cancels callers ask for. So no refill overlaps
/// another or a completion, a cancel returns after the completions before
/// it, and the end of a background launch's events is handled after all of
/// them.
///
/// One instance per app process; the Share Extension never builds one, so
/// only the app owns the session's identifier.
@MainActor
@Observable
public final class LibraryFileDownloader {
  public nonisolated static let sessionIdentifier = "com.paulgessinger.swift-paperless.files"

  /// How long a refill waits for a server's repository. Past it, the refill
  /// gives up, so the events behind it are not held up.
  public static let repositoryTimeout = Duration.seconds(10)

  /// How long after iOS relaunched the app for the session's events its
  /// handler is called, even if the loop has not handled them all: iOS
  /// allows about 30 seconds.
  public static let backgroundEventsDeadline = Duration.seconds(20)

  public typealias ServerLookup = @MainActor (UUID) async throws -> LibraryDownloadServer?

  public enum RefillOutcome: Equatable, Sendable {
    /// Handed this many new tasks to the session.
    case queued(Int)
    /// Nothing is missing, or the server is gone.
    case complete
    /// Free space is below the floor; nothing was queued.
    case pausedLowStorage
  }

  /// Tasks in flight per server. Throttled for display: eight fast downloads
  /// change it many times a second.
  public private(set) var inFlight: [UUID: Int] = [:]
  /// Whether the last refill stopped because free space is below the floor.
  public private(set) var pausedLowStorage = false

  /// A download that failed, for the server's failure ledger.
  @ObservationIgnored public var onFailure: (@MainActor (UUID, any Error) -> Void)?

  /// Set by `AppDelegate` when iOS relaunched the app for the session's
  /// events. Called once: when the loop has handled them, at the deadline,
  /// or when the background time runs out, whichever comes first.
  @ObservationIgnored public var backgroundEventsCompletion: (() -> Void)? {
    didSet { startEventsDeadline() }
  }

  /// What is missing: the candidates a refill queues.
  private let database: Database
  /// Where finished files go, moved in by the delegate.
  private let store: ContentStore
  /// Where a finished file is recorded.
  private let index: any FileIndex
  /// Keeps the database open while an event is handled in the background.
  private let suspension: DatabaseSuspensionController
  /// A server's mode, cellular policy and repository, `nil` once it is gone.
  private let servers: ServerLookup
  /// The servers the launch refill covers.
  private let allServerIDs: @MainActor () -> [UUID]
  /// Free space on the store's volume, checked against the floor.
  private let availableCapacity: @Sendable (URL) -> Int64?
  /// How many downloads a server keeps in flight.
  private let window: Int
  /// How long a refill waits for a server's repository.
  private let repositoryTimeout: Duration
  /// Coalesces ``inFlight`` updates to the screen's cadence.
  private let display: UpdateThrottle
  /// How long after a handler is set it is called regardless.
  private let backgroundEventsDeadline: Duration
  /// Feeds the loop: the delegate's completions and the callers' requests.
  private let events: AsyncStream<Event>.Continuation
  /// The session's delegate, which passes its events to ``events``.
  private let delegate: Delegate
  /// The background session the downloads run on.
  private let session: URLSession

  /// The tasks in flight: taken from the session when the loop starts, then
  /// kept by the loop as it queues and files them.
  @ObservationIgnored private var tasks: [Int: (task: URLSessionTask, id: TaskID)] = [:]
  /// Documents whose download failed, left alone for an hour.
  @ObservationIgnored private var recentlyFailed: [ContentStore.Key: Date] = [:]
  /// Servers with a task filed since their last refill. Refilled together
  /// once the events queued behind the first are handled.
  @ObservationIgnored private var needsRefill: Set<UUID> = []
  /// Set once a test shut the session down: refills then queue nothing.
  @ObservationIgnored private var isInvalidated = false

  /// - Parameters:
  ///   - servers: the server to queue for, `nil` for one that is gone.
  ///   - allServerIDs: the servers a refill of every window covers.
  ///   - identityName: the client-certificate identity of a server, read on
  ///     the session's queue.
  ///   - makeSession: the session over the delegate; the background
  ///     configuration in production, a stubbed one in tests.
  public init(
    database: Database, store: ContentStore, index: any FileIndex,
    suspension: DatabaseSuspensionController, servers: @escaping ServerLookup,
    allServerIDs: @escaping @MainActor () -> [UUID],
    identityName: @escaping @Sendable (UUID) -> String?,
    availableCapacity: @escaping @Sendable (URL) -> Int64? = LibraryFileDownloader.volumeCapacity,
    window: Int = StoragePolicy.libraryDownloadWindow,
    displayInterval: Duration = UpdateThrottle.displayInterval,
    repositoryTimeout: Duration = LibraryFileDownloader.repositoryTimeout,
    backgroundEventsDeadline: Duration = LibraryFileDownloader.backgroundEventsDeadline,
    makeSession: (URLSessionDownloadDelegate) -> URLSession = LibraryFileDownloader
      .makeBackgroundSession
  ) {
    self.database = database
    self.store = store
    self.index = index
    self.suspension = suspension
    self.servers = servers
    self.allServerIDs = allServerIDs
    self.availableCapacity = availableCapacity
    self.window = window
    self.repositoryTimeout = repositoryTimeout
    self.display = UpdateThrottle(interval: displayInterval)
    self.backgroundEventsDeadline = backgroundEventsDeadline
    let (stream, events) = AsyncStream.makeStream(of: Event.self)
    self.events = events
    // Before the session exists, so it comes before any of its events.
    events.yield(.start)
    let delegate = Delegate(store: store, events: events, identityName: identityName)
    self.delegate = delegate
    self.session = makeSession(delegate)
    Task { @MainActor [weak self] in
      for await event in stream {
        guard let self else { break }
        await self.handle(event)
      }
    }
  }

  /// `URLSessionConfiguration.background`: the system runs the tasks while
  /// the app is suspended and relaunches it for their events. Cellular and
  /// Low Data Mode are decided per task.
  public nonisolated static func makeBackgroundSession(delegate: URLSessionDownloadDelegate)
    -> URLSession
  {
    let configuration = URLSessionConfiguration.background(withIdentifier: sessionIdentifier)
    configuration.isDiscretionary = false
    configuration.sessionSendsLaunchEvents = true
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }

  /// Free space for data the user asked for, on the volume `url` is on.
  public nonisolated static func volumeCapacity(of url: URL) -> Int64? {
    try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
  }

  // MARK: - Requests

  /// Top the server's window up. Returns once the tasks are queued; the
  /// downloads run on the session.
  @discardableResult
  public func refill(serverID: UUID) async throws -> RefillOutcome {
    guard !isInvalidated else { return .complete }
    return try await withCheckedThrowingContinuation { events.yield(.refill(serverID, $0)) }
  }

  /// Top every server's window up, after iOS relaunched the app for the
  /// session's events or at launch.
  public func refillAllServers() async {
    for serverID in allServerIDs() {
      do {
        try await refill(serverID: serverID)
      } catch {
        Logger.sync.error("Library file refill failed: \(error)")
      }
    }
  }

  /// Call off a server's downloads: it was removed, or left *Entire library*
  /// (a refill then queues the kept documents again). Returns once the
  /// completions that arrived before it are filed, so a caller reclaiming
  /// the server's files runs after them; a completion that arrives later
  /// finds the server no longer wants the file and drops it.
  public func cancel(serverID: UUID) async {
    await withCheckedContinuation { events.yield(.cancel(serverID, $0)) }
  }

  public func cancelAll() async {
    await withCheckedContinuation { events.yield(.cancel(nil, $0)) }
  }

  /// Call iOS's handler now, if there is one.
  public func finishBackgroundEvents() {
    let handler = backgroundEventsCompletion
    backgroundEventsCompletion = nil
    handler?()
  }

  /// What the delegate does when the session's events are all delivered,
  /// waiting until the loop has handled them. For tests.
  func backgroundEventsDidFinish() async {
    await withCheckedContinuation { events.yield(.eventsDone($0)) }
  }

  /// Replaces the deadline of the handler before, so a later launch's
  /// handler is not called on an earlier launch's clock.
  @ObservationIgnored private var eventsDeadline: Task<Void, Never>?

  private func startEventsDeadline() {
    eventsDeadline?.cancel()
    eventsDeadline = nil
    guard backgroundEventsCompletion != nil else { return }
    eventsDeadline = Task { [weak self, backgroundEventsDeadline] in
      try? await Task.sleep(for: backgroundEventsDeadline)
      guard !Task.isCancelled else { return }
      self?.finishBackgroundEvents()
    }
  }

  /// Shut the session down, cancelling its tasks, and wait until it lists
  /// none. For a test's downloader; the app's lives as long as the process.
  func invalidate() async {
    isInvalidated = true
    session.invalidateAndCancel()
    for _ in 0..<100 where await !session.allTasks.isEmpty {
      try? await Task.sleep(for: .milliseconds(10))
    }
    // A cancelled task's loader can still be starting; let it settle.
    try? await Task.sleep(for: .milliseconds(20))
  }

  // MARK: - The loop

  fileprivate typealias TaskID = (key: ContentStore.Key, documentID: UInt, modified: Date)

  fileprivate enum Event: Sendable {
    /// First, once: the tasks the session already holds.
    case start
    /// A task ended: `size` when its file is in the store, else `error`.
    case finished(task: Int, id: TaskID, size: Int64?, error: (any Error)?)
    case refill(UUID, CheckedContinuation<RefillOutcome, any Error>)
    /// `nil` calls off every server's.
    case cancel(UUID?, CheckedContinuation<Void, Never>)
    /// Refill the servers in ``needsRefill``.
    case refillFiled
    /// iOS delivered every event it relaunched the app for.
    case eventsDone(CheckedContinuation<Void, Never>?)
  }

  private func handle(_ event: Event) async {
    switch event {
    case .start:
      for task in await session.allTasks
      where task.state == .running || task.state == .suspended {
        if let id = task.taskDescription.flatMap(LibraryFileTaskID.parse) {
          tasks[task.taskIdentifier] = (task, id)
        }
      }
      publish()
    case .finished(let task, let id, let size, let error):
      await suspension.performBackgroundWork {
        await file(task: task, id: id, size: size, error: error)
      }
    case .refill(let serverID, let reply):
      do {
        let outcome = try await suspension.performBackgroundWork {
          try await performRefill(serverID: serverID)
        }
        reply.resume(returning: outcome)
      } catch {
        reply.resume(throwing: error)
      }
    case .cancel(let serverID, let reply):
      for (identifier, entry) in tasks where serverID == nil || entry.id.key.serverID == serverID {
        entry.task.cancel()
        tasks[identifier] = nil
      }
      publish()
      reply.resume()
    case .refillFiled:
      await refillFiled()
    case .eventsDone(let reply):
      // Queued before iOS suspends the app again, so the window keeps going.
      await refillFiled()
      finishBackgroundEvents()
      reply?.resume()
    }
  }

  /// File a finished task: record its file, or drop one its server no longer
  /// wants (the server left *Entire library*, the document is no longer
  /// kept, or the server is gone, and the reclaim may already have run), or
  /// note the failure. Its server is refilled once
  /// the events already queued are handled.
  private func file(task: Int, id: TaskID, size: Int64?, error: (any Error)?) async {
    tasks[task] = nil
    publish()
    let serverID = id.key.serverID
    if let size {
      if await isWanted(id) {
        do {
          try await index.recordStore(
            id.key, documentID: id.documentID, size: size, modified: id.modified,
            checksum: nil, storedAt: Date())
        } catch {
          // The repair walk removes a rowless file after an hour and the
          // next pass downloads it again.
          Logger.sync.error("Recording a library file failed: \(error)")
        }
      } else {
        do {
          try store.delete(id.key)
        } catch {
          // Unindexed: the repair walk removes it after an hour.
          Logger.sync.error("Dropping an unwanted library file failed: \(error)")
        }
      }
    } else if let error, (error as? URLError)?.code != .cancelled {
      recentlyFailed[id.key] = Date()
      onFailure?(serverID, error)
    }
    if needsRefill.isEmpty {
      events.yield(.refillFiled)
    }
    needsRefill.insert(serverID)
  }

  /// Whether the file is still in its server's scope.
  private func isWanted(_ id: TaskID) async -> Bool {
    guard let server = try? await servers(id.key.serverID) else { return false }
    if server.isEntireLibrary { return true }
    let kept = (try? await database.keptOfflineIDs(serverID: id.key.serverID)) ?? []
    return kept.contains(id.documentID)
  }

  private func refillFiled() async {
    let serverIDs = needsRefill
    needsRefill = []
    for serverID in serverIDs {
      do {
        try await suspension.performBackgroundWork {
          _ = try await performRefill(serverID: serverID)
        }
      } catch {
        Logger.sync.error("Library file refill failed: \(error)")
      }
    }
  }

  private func performRefill(serverID: UUID) async throws -> RefillOutcome {
    guard !isInvalidated, let server = try await servers(serverID) else { return .complete }
    if let free = availableCapacity(store.root),
      free < StoragePolicy.libraryDownloadFreeSpaceFloorBytes
    {
      if !pausedLowStorage { pausedLowStorage = true }
      return .pausedLowStorage
    }
    if pausedLowStorage { pausedLowStorage = false }

    let inFlightDocuments = Set(
      tasks.values.filter { $0.id.key.serverID == serverID }.map(\.id.documentID))
    let room = window - inFlightDocuments.count
    guard room > 0 else { return .queued(0) }
    let now = Date()
    recentlyFailed = recentlyFailed.filter { now.timeIntervalSince($0.value) < 3600 }
    let backedOff = Set(recentlyFailed.keys.filter { $0.serverID == serverID }.map(\.versionID))
    let candidates = try await database.documentsNeedingArchive(
      serverID: serverID, scope: server.scope, excluding: inFlightDocuments,
      limit: room + backedOff.count
    ).filter { !backedOff.contains($0.versionID) }.prefix(room)
    guard !candidates.isEmpty else { return .complete }

    let repository = try await withTimeout(repositoryTimeout) { try await server.repository() }
    for candidate in candidates {
      let key = ContentStore.Key(
        serverID: serverID, versionID: candidate.versionID, kind: .archive)
      var request = try repository.downloadRequest(
        documentID: candidate.documentID, version: candidate.versionQueryID)
      request.allowsExpensiveNetworkAccess = server.syncOverCellular
      request.allowsConstrainedNetworkAccess = false
      let task = session.downloadTask(with: request)
      task.taskDescription = LibraryFileTaskID.make(
        key: key, documentID: candidate.documentID, modified: candidate.modified)
      tasks[task.taskIdentifier] = (task, (key, candidate.documentID, candidate.modified))
      task.resume()
    }
    publish()
    return .queued(candidates.count)
  }

  private func publish() {
    display.run { [weak self] in
      guard let self else { return }
      var counts: [UUID: Int] = [:]
      for entry in tasks.values {
        counts[entry.id.key.serverID, default: 0] += 1
      }
      if inFlight != counts { inFlight = counts }
    }
  }

  // MARK: - Delegate

  /// Runs on the session's delegate queue, which is serial. Moves a finished
  /// file into the store at once, since iOS deletes it when the callback
  /// returns, and passes every event on to the loop in order.
  private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    /// Where a finished file is moved, inside its callback.
    private let store: ContentStore
    /// The loop's events, yielded in the order the session delivers them.
    private let events: AsyncStream<Event>.Continuation
    /// A server's client-certificate identity, for its challenges.
    private let identityName: @Sendable (UUID) -> String?
    /// Files moved into the store, by task, until the task completes. Only
    /// touched on the delegate queue.
    private var stored: [Int: Int64] = [:]

    init(
      store: ContentStore, events: AsyncStream<Event>.Continuation,
      identityName: @escaping @Sendable (UUID) -> String?
    ) {
      self.store = store
      self.events = events
      self.identityName = identityName
    }

    func urlSession(
      _ session: URLSession, downloadTask: URLSessionDownloadTask,
      didFinishDownloadingTo location: URL
    ) {
      guard let id = downloadTask.taskDescription.flatMap(LibraryFileTaskID.parse),
        (downloadTask.response as? HTTPURLResponse)?.statusCode == 200
      else { return }
      do {
        try store.store(id.key, movingFrom: location)
        stored[downloadTask.taskIdentifier] =
          store.size(of: id.key) ?? downloadTask.countOfBytesReceived
      } catch {
        Logger.sync.error("Storing a library file failed: \(error)")
      }
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
      guard let id = task.taskDescription.flatMap(LibraryFileTaskID.parse) else { return }
      NetworkTransfer.record(bytes: Int(task.countOfBytesReceived), category: .libraryFiles)
      let size = stored.removeValue(forKey: task.taskIdentifier)
      let failure = size == nil ? error ?? Self.failure(for: task.response) : nil
      events.yield(.finished(task: task.taskIdentifier, id: id, size: size, error: failure))
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
      guard
        challenge.protectionSpace.authenticationMethod
          == NSURLAuthenticationMethodClientCertificate,
        let id = task.taskDescription.flatMap(LibraryFileTaskID.parse),
        let name = identityName(id.key.serverID),
        let identity = Keychain.readIdentity(name: name)
      else { return (.performDefaultHandling, nil) }
      return (.useCredential, PaperlessURLSessionDelegate.credential(for: identity))
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
      events.yield(.eventsDone(nil))
    }

    /// The same reading of a response as the on-demand download's.
    private static func failure(for response: URLResponse?) -> any Error {
      guard let http = response as? HTTPURLResponse, let status = http.status else {
        return RequestError.invalidResponse
      }
      switch status {
      case .forbidden: return RequestError.forbidden(detail: nil)
      case .unauthorized: return RequestError.unauthorized(detail: "")
      case .notAcceptable: return RequestError.unsupportedVersion(sentVersion: nil)
      default: return RequestError.unexpectedStatusCode(code: status, detail: nil)
      }
    }
  }
}

/// Run `body`, giving up with ``TimeoutError`` after `limit`. The work is
/// cancelled but not waited for, so a body that ignores cancellation cannot
/// hold the caller.
@MainActor
private func withTimeout<T: Sendable>(
  _ limit: Duration, _ body: @escaping @MainActor @Sendable () async throws -> T
) async throws -> T {
  let gate = OnceGate()
  return try await withCheckedThrowingContinuation { continuation in
    let work = Task { @MainActor in try await body() }
    let timer = Task { @MainActor in
      try await Task.sleep(for: limit)
      if gate.open() {
        work.cancel()
        continuation.resume(throwing: TimeoutError())
      }
    }
    Task { @MainActor in
      let result = await work.result
      if gate.open() {
        timer.cancel()
        continuation.resume(with: result)
      }
    }
  }
}

struct TimeoutError: Error {}

@MainActor
private final class OnceGate {
  private var isOpen = false

  /// True the first time only.
  func open() -> Bool {
    guard !isOpen else { return false }
    isOpen = true
    return true
  }
}
