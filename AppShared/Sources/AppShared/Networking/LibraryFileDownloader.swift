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
  /// Builds the authenticated requests.
  public let repository: any Repository
  public let syncOverCellular: Bool
  public let isEntireLibrary: Bool

  public init(repository: any Repository, syncOverCellular: Bool, isEntireLibrary: Bool) {
    self.repository = repository
    self.syncOverCellular = syncOverCellular
    self.isEntireLibrary = isEntireLibrary
  }
}

/// Keeps a window of archive downloads in flight for every *Entire library*
/// server. The index is the source of truth: a refill asks the database for
/// the newest documents whose archive is missing or outdated, skips the ones
/// the session already holds, and hands iOS the rest, up to the window. A
/// finished task's file is moved into the store inside the callback, its row
/// is recorded, and the window is refilled.
///
/// One instance per app process; the Share Extension never builds one, so
/// only the app owns the session's identifier.
@MainActor
@Observable
public final class LibraryFileDownloader {
  public nonisolated static let sessionIdentifier = "com.paulgessinger.swift-paperless.files"

  public typealias ServerLookup = @MainActor (UUID) async throws -> LibraryDownloadServer?

  public enum RefillOutcome: Equatable, Sendable {
    /// Handed this many new tasks to the session.
    case queued(Int)
    /// Nothing is missing, or the server is not in *Entire library*.
    case complete
    /// Free space is below the floor; nothing was queued.
    case pausedLowStorage
  }

  /// Tasks in flight per server, from the session's own list. Throttled for
  /// display: eight fast downloads change it many times a second.
  public private(set) var inFlight: [UUID: Int] = [:]
  public private(set) var pausedLowStorage = false
  /// The download row per server while its tasks run, throttled with
  /// ``inFlight``.
  public private(set) var activities: [UUID: SyncActivity] = [:]

  /// What ``inFlight`` and ``activities`` show, as the downloader tracks it.
  @ObservationIgnored private var running: [UUID: Int] = [:] {
    didSet { publish() }
  }
  @ObservationIgnored private var rows: [UUID: SyncActivity] = [:] {
    didSet { publish() }
  }
  @ObservationIgnored private let display: UpdateThrottle
  /// A download that failed, for the server's failure ledger.
  public var onFailure: (@MainActor (UUID, any Error) -> Void)?
  /// Set by `AppDelegate` when iOS relaunched the app for the session's
  /// events; called once they are handled.
  public var backgroundEventsCompletion: (() -> Void)?

  private let database: Database
  private let store: ContentStore
  private let index: any FileIndex
  private let suspension: DatabaseSuspensionController
  private let servers: ServerLookup
  private let allServerIDs: @MainActor () -> [UUID]
  private let availableCapacity: @Sendable (URL) -> Int64?
  private let window: Int
  private let session: URLSession
  private let delegate: Delegate
  /// Documents whose download failed, left alone for an hour.
  private var recentlyFailed: [ContentStore.Key: Date] = [:]
  /// One refill at a time per server, whoever asks: two refills reading the
  /// same in-flight tasks would both queue the same documents.
  private var refills: [UUID: TaskSlot<RefillOutcome, any Error>] = [:]
  /// Servers whose refill was asked for while one was running; it runs again.
  private var refillRequested: Set<UUID> = []
  private var isInvalidated = false

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
    self.display = UpdateThrottle(interval: displayInterval)
    let delegate = Delegate(store: store, identityName: identityName)
    self.delegate = delegate
    self.session = makeSession(delegate)
    delegate.owner = self
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

  // MARK: - Queueing

  /// Top the server's window up. Returns once the tasks are queued; the
  /// downloads run on the session. A refill asked for while one runs joins
  /// it, and that one runs once more, so it sees the tasks the first queued.
  @discardableResult
  public func refill(serverID: UUID) async throws -> RefillOutcome {
    let slot = refills[serverID] ?? TaskSlot()
    refills[serverID] = slot
    if slot.isOccupied {
      refillRequested.insert(serverID)
    }
    let operation: @MainActor () async throws -> RefillOutcome = {
      var outcome: RefillOutcome
      repeat {
        self.refillRequested.remove(serverID)
        outcome = try await self.performRefill(serverID: serverID)
      } while self.refillRequested.contains(serverID)
      return outcome
    }
    var outcome = try await slot.joinOrStart(operation)
    // Joined a refill that had already finished: the request is still
    // standing, and the slot is free now.
    while refillRequested.contains(serverID) {
      outcome = try await slot.joinOrStart(operation)
    }
    return outcome
  }

  private func performRefill(serverID: UUID) async throws -> RefillOutcome {
    guard !isInvalidated, let server = try await servers(serverID), server.isEntireLibrary else {
      rows[serverID] = nil
      return .complete
    }
    let inFlightDocuments = await refreshInFlight()[serverID] ?? []
    defer { Task { await publishActivity(serverID) } }

    if let free = availableCapacity(store.root),
      free < StoragePolicy.libraryDownloadFreeSpaceFloorBytes
    {
      if !pausedLowStorage { pausedLowStorage = true }
      return .pausedLowStorage
    }
    if pausedLowStorage { pausedLowStorage = false }

    let room = window - inFlightDocuments.count
    guard room > 0 else { return .queued(0) }
    let now = Date()
    recentlyFailed = recentlyFailed.filter { now.timeIntervalSince($0.value) < 3600 }
    let backedOff = Set(recentlyFailed.keys.filter { $0.serverID == serverID }.map(\.versionID))
    let candidates = try await database.documentsNeedingArchive(
      serverID: serverID, excluding: inFlightDocuments, limit: room + backedOff.count)
    var queued = 0
    for candidate in candidates where queued < room {
      let key = ContentStore.Key(
        serverID: serverID, versionID: candidate.versionID, kind: .archive)
      guard !backedOff.contains(key.versionID) else { continue }
      var request = try server.repository.downloadRequest(
        documentID: candidate.documentID, version: candidate.versionQueryID)
      request.allowsExpensiveNetworkAccess = server.syncOverCellular
      request.allowsConstrainedNetworkAccess = false
      let task = session.downloadTask(with: request)
      task.taskDescription = LibraryFileTaskID.make(
        key: key, documentID: candidate.documentID, modified: candidate.modified)
      task.resume()
      queued += 1
    }
    running[serverID, default: 0] += queued
    return queued > 0 ? .queued(queued) : .complete
  }

  /// Top every server's window up, after iOS relaunched the app for the
  /// session's events or at launch.
  public func refillAllLibraryServers() async {
    for serverID in allServerIDs() {
      do {
        try await refill(serverID: serverID)
      } catch {
        Logger.sync.error("Library file refill failed: \(error)")
      }
    }
  }

  /// Call off a server's downloads: it was removed, or left *Entire library*.
  /// Returns once the completions already handed over are filed, so a caller
  /// reclaiming the server's files runs after them; a completion handed over
  /// later finds the server no longer wants the file and drops it.
  public func cancel(serverID: UUID) async {
    for (task, id) in await describedTasks() where id.key.serverID == serverID {
      task.cancel()
    }
    for handoff in delegate.pendingHandoffs(serverID: serverID) {
      await handoff.value
    }
    running[serverID] = nil
    rows[serverID] = nil
  }

  public func cancelAll() async {
    for (task, _) in await describedTasks() {
      task.cancel()
    }
    for handoff in delegate.pendingHandoffs() {
      await handoff.value
    }
    running = [:]
    rows = [:]
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

  // MARK: - Completions

  /// The session's tasks that are this downloader's, with their ids. A task
  /// the delegate saw complete can still be listed as running for a moment;
  /// it is left out so the window it held is refilled.
  private func describedTasks() async -> [(URLSessionTask, LibraryFileTaskID.Parsed)] {
    let tasks = await session.allTasks
    let finished = delegate.pruneFinished(keeping: Set(tasks.map(\.taskIdentifier)))
    return tasks.compactMap { task in
      guard task.state != .canceling, task.state != .completed,
        !finished.contains(task.taskIdentifier),
        let id = task.taskDescription.flatMap(LibraryFileTaskID.parse)
      else { return nil }
      return (task, id)
    }
  }

  /// Re-read the in-flight documents per server from the session.
  private func refreshInFlight() async -> [UUID: Set<UInt>] {
    var documents: [UUID: Set<UInt>] = [:]
    for (_, id) in await describedTasks() {
      documents[id.key.serverID, default: []].insert(id.documentID)
    }
    running = documents.mapValues(\.count)
    return documents
  }

  private func publish() {
    display.run { [weak self] in
      guard let self else { return }
      if inFlight != running { inFlight = running }
      if activities != rows { activities = rows }
    }
  }

  private func publishActivity(_ serverID: UUID) async {
    guard (running[serverID] ?? 0) > 0,
      let progress = try? await database.libraryFileProgress(serverID: serverID)
    else {
      rows[serverID] = nil
      return
    }
    rows[serverID] = SyncActivity(
      stage: .fileDownload, completed: progress.downloadedFiles, total: progress.totalDocuments)
  }

  /// A task's file is in the store; record it, then refill. A server that
  /// no longer wants it, having left *Entire library* or gone, gets the file
  /// dropped instead: its reclaim may already have run.
  fileprivate func didStore(_ id: LibraryFileTaskID.Parsed, size: Int64) async {
    await suspension.performBackgroundWork {
      guard let server = try? await servers(id.key.serverID), server.isEntireLibrary else {
        do {
          try store.delete(id.key)
        } catch {
          // Unindexed: the repair walk removes it after an hour.
          Logger.sync.error("Dropping an unwanted library file failed: \(error)")
        }
        return
      }
      do {
        try await index.recordStore(
          id.key, documentID: id.documentID, size: size, modified: id.modified, checksum: nil,
          storedAt: Date())
      } catch {
        // The repair walk removes a rowless file after an hour and the next
        // pass downloads it again.
        Logger.sync.error("Recording a library file failed: \(error)")
      }
    }
    await didFinish(id)
  }

  fileprivate func didFail(_ id: LibraryFileTaskID.Parsed, error: any Error) async {
    if !(error is CancellationError), (error as? URLError)?.code != .cancelled {
      recentlyFailed[id.key] = Date()
      onFailure?(id.key.serverID, error)
    }
    await didFinish(id)
  }

  /// The task's slot is free: refill, and return once the refill ran.
  private func didFinish(_ id: LibraryFileTaskID.Parsed) async {
    let serverID = id.key.serverID
    running[serverID] = max(0, (running[serverID] ?? 1) - 1)
    await suspension.performBackgroundWork {
      do {
        try await refill(serverID: serverID)
      } catch {
        Logger.sync.error("Library file refill failed: \(error)")
      }
    }
  }

  /// Every event iOS relaunched the app for is handled; let it suspend the
  /// app again once the completions are filed and their refills ran. The
  /// session reports this after every task event, so each completion has
  /// been handed over by now.
  func backgroundEventsDidFinish() async {
    for handoff in delegate.pendingHandoffs() {
      await handoff.value
    }
    for slot in refills.values {
      await slot.waitUntilIdle()
    }
    let completion = backgroundEventsCompletion
    backgroundEventsCompletion = nil
    completion?()
  }

  // MARK: - Delegate

  /// Runs on the session's queue. Moves a finished file into the store at
  /// once, since iOS deletes it when the callback returns, and hands the
  /// rest to the downloader on the main actor.
  private final class Delegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    weak var owner: LibraryFileDownloader?
    private let store: ContentStore
    private let identityName: @Sendable (UUID) -> String?
    private let lock = NSLock()
    /// Files moved into the store, by task, until the task completes.
    private var stored: [Int: Int64] = [:]
    /// Tasks that completed, until the session stops listing them.
    private var finished: Set<Int> = []
    /// The work each completion handed to the downloader, by task, until it
    /// is done: what the background events completion and a cancel wait on.
    private var handoffs: [Int: (serverID: UUID, task: Task<Void, Never>)] = [:]

    /// The completions handed over and not yet filed, of one server or all.
    func pendingHandoffs(serverID: UUID? = nil) -> [Task<Void, Never>] {
      lock.withLock {
        handoffs.values.filter { serverID == nil || $0.serverID == serverID }.map(\.task)
      }
    }

    /// Hand a completion to the downloader, registered before this callback
    /// returns.
    private func handOff(
      _ task: URLSessionTask, serverID: UUID, _ work: @escaping @MainActor () async -> Void
    ) {
      let identifier = task.taskIdentifier
      lock.withLock {
        let handoff = Task { @MainActor in
          await work()
          self.lock.withLock { _ = self.handoffs.removeValue(forKey: identifier) }
        }
        handoffs[identifier] = (serverID, handoff)
      }
    }

    /// Forget the finished tasks the session no longer lists; returns the rest.
    func pruneFinished(keeping listed: Set<Int>) -> Set<Int> {
      lock.withLock {
        finished.formIntersection(listed)
        return finished
      }
    }

    init(store: ContentStore, identityName: @escaping @Sendable (UUID) -> String?) {
      self.store = store
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
        let size = store.size(of: id.key) ?? downloadTask.countOfBytesReceived
        lock.withLock { stored[downloadTask.taskIdentifier] = size }
      } catch {
        Logger.sync.error("Storing a library file failed: \(error)")
      }
    }

    func urlSession(
      _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
    ) {
      guard let id = task.taskDescription.flatMap(LibraryFileTaskID.parse) else { return }
      NetworkTransfer.record(bytes: Int(task.countOfBytesReceived), category: .libraryFiles)
      let size = lock.withLock {
        finished.insert(task.taskIdentifier)
        return stored.removeValue(forKey: task.taskIdentifier)
      }
      let owner = owner
      if let size {
        handOff(task, serverID: id.key.serverID) { await owner?.didStore(id, size: size) }
        return
      }
      let failure = error ?? Self.failure(for: task.response)
      handOff(task, serverID: id.key.serverID) { await owner?.didFail(id, error: failure) }
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
      let owner = owner
      Task { @MainActor in await owner?.backgroundEventsDidFinish() }
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

extension LibraryFileTaskID {
  typealias Parsed = (key: ContentStore.Key, documentID: UInt, modified: Date)
}
