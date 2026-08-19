//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Common
import CryptoKit
import DataModel
import Foundation
import Networking
import Persistence
import os

public struct StoredConnection: Equatable, Identifiable, Sendable {
  public var id: UUID = .init()
  public var url: URL
  public var extraHeaders: [Connection.HeaderValue]
  public var user: User
  public var identity: String?
  public var friendlyName: String? = nil
  public var offlineBrowsingMode: OfflineBrowsingMode = .recentlyBrowsed

  public init(
    id: UUID = .init(),
    url: URL,
    extraHeaders: [Connection.HeaderValue],
    user: User,
    identity: String? = nil,
    friendlyName: String? = nil,
    offlineBrowsingMode: OfflineBrowsingMode = .recentlyBrowsed
  ) {
    self.id = id
    self.url = url
    self.extraHeaders = extraHeaders
    self.user = user
    self.identity = identity
    self.friendlyName = friendlyName
    self.offlineBrowsingMode = offlineBrowsingMode
  }

  public var token: String? {
    get throws {
      Logger.api.debug("Loading token from keychain for \(user.username) \(url.absoluteString)")
      guard
        let data = try Keychain.read(
          service: url.absoluteString,
          account: user.username)
      else {
        Logger.api.info("Read nil valuefrom keychain, return nil")
        return nil
      }
      let token = String(data: data, encoding: .utf8)!
      // we might have saved empty strings as tokens before, convert to nil when reading
      if token.isEmpty {
        Logger.api.info("Read empty string from keychain, return nil")
        return nil
      }
      return token
    }
  }

  public func setToken(_ token: String) throws(Keychain.KeychainError) {
    Logger.api.debug("Saving token \(token) to keychain for \(user.username) \(url.absoluteString)")
    try Keychain.saveOrUpdate(
      service: url.absoluteString,
      account: user.username,
      value: token.data(using: .utf8)!)
  }

  public var connection: Connection {
    get throws {
      try Connection(
        url: url, token: token, extraHeaders: extraHeaders,
        identityName: identity, serverID: id)
    }
  }

  public var fullLabel: String {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      Logger.api.error("Valid stored connection's URL could not be decomposed")
      return "\(user.username)@\(url)"
    }
    components.user = user.username
    guard let urlString = components.url?.absoluteString else {
      Logger.api.error("Decomposed URL could not be reformed")
      return "\(user.username)@\(url)"
    }
    return urlString
  }

  public var label: String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      Logger.api.error("Valid stored connection's URL could not be decomposed")
      return "\(user.username)@\(url)"
    }

    guard var urlString = components.host else {
      return "\(user.username)@\(url)"
    }

    if components.path != "" {
      if urlString.last != "/", components.path.first != "/" {
        urlString += "/"
      }
      urlString += "\(components.path)"
    }
    return "\(user.username)@\(urlString)"
  }

  public var shortLabel: String {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      Logger.api.error("Valid stored connection's URL could not be decomposed")
      return "\(user.username)@\(url)"
    }
    guard var urlString = components.host else {
      return "\(user.username)@\(url)"
    }

    if let scheme = components.scheme {
      urlString = "\(scheme)://\(urlString)"
    }

    if let port = components.port, port != 80, port != 443 {
      urlString = "\(urlString):\(port)"
    }

    if components.path != "" {
      if urlString.last != "/", components.path.first != "/" {
        urlString += "/"
      }
      urlString += "\(components.path)"
    }
    return urlString
  }

  public var redactedLabel: String {
    #if DEBUG
      return fullLabel
    #else
      let pid = ProcessInfo.processInfo.processIdentifier

      guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        Logger.api.error("Valid stored connection's URL could not be decomposed")
        return "<unavailable>"
      }

      let userHash = SHA256.hash(data: "\(pid)\(user.username)".data(using: .utf8)!).compactMap {
        String(format: "%02x", $0)
      }.joined().prefix(8)
      let urlHash = SHA256.hash(data: "\(pid)\(url)".data(using: .utf8)!).compactMap {
        String(format: "%02x", $0)
      }.joined().prefix(8)

      components.user = "user-\(userHash)"
      components.host = "\(urlHash).example.com"
      guard let result = components.url else {
        Logger.api.error("Decomposed URL could not be reformed")
        return "<unavailable>"
      }

      return result.absoluteString
    #endif
  }
}

@MainActor
@Observable
public final class ConnectionManager {
  private struct PreviewLaunchArguments {
    let mode: Bool?
    let url: String?
    let token: String?

    var effectiveMode: Bool? {
      if let mode {
        return mode
      }
      if url != nil || token != nil {
        return true
      }
      return nil
    }

    static func parse(_ args: [String]) -> PreviewLaunchArguments? {
      var mode: Bool? = nil
      var url: String? = nil
      var token: String? = nil
      var index = 0

      while index < args.count {
        let arg = args[index]
        switch arg {
        case "--preview-mode":
          mode = true
        case "--preview-url":
          if index + 1 < args.count {
            url = args[index + 1]
            index += 1
          }
        case "--preview-token":
          if index + 1 < args.count {
            token = args[index + 1]
            index += 1
          }
        default:
          if arg.hasPrefix("--preview-mode=") {
            let value = String(arg.dropFirst("--preview-mode=".count))
            let lowercased = value.lowercased()
            mode = !(lowercased == "0" || lowercased == "false" || lowercased == "no")
          } else if arg.hasPrefix("--preview-url=") {
            url = String(arg.dropFirst("--preview-url=".count))
          } else if arg.hasPrefix("--preview-token=") {
            token = String(arg.dropFirst("--preview-token=".count))
          }
        }
        index += 1
      }

      if mode == nil && url == nil && token == nil {
        return nil
      }
      return PreviewLaunchArguments(mode: mode, url: url, token: token)
    }
  }

  public enum Event: Sendable {
    case connectionChange(animated: Bool)
    case logout
  }

  public let events = Broadcaster<Event>()

  @ObservationIgnored
  private let previewArguments: PreviewLaunchArguments?
  public let previewMode: Bool

  @ObservationIgnored
  private let database: Database
  @ObservationIgnored
  private var observationTask: Task<Void, Never>?

  public init(database: Database, previewMode: Bool? = nil) {
    self.database = database
    let previewArguments = PreviewLaunchArguments.parse(ProcessInfo.processInfo.arguments)
    self.previewArguments = previewArguments
    if let previewMode {
      self.previewMode = previewMode
    } else if let previewMode = previewArguments?.effectiveMode {
      self.previewMode = previewMode
    } else {
      self.previewMode = false
    }

    // Synchronous bootstrap read so SwiftUI body sees the cache populated
    // before the first frame. Subsequent updates come via the observer.
    do {
      let records = try database.allConnections()
      applyHydrate(records: records)
    } catch {
      Logger.shared.fault("Initial connection hydrate failed: \(error)")
    }

    // The observer is the *authoritative* writer of the in-memory dict, but
    // not the only one: mutators apply their change eagerly so the very next
    // synchronous read sees it, and the observer reconciles a tick later.
    // `applyHydrate` is equality-guarded, so the reconcile is a no-op unless
    // the DB actually disagrees with what the mutator assumed.
    //
    // The observation's own first value is consumed like any other rather
    // than discarded as "already applied by the bootstrap read above": a
    // write landing between that read and the observation's initial fetch is
    // baked into the first value, and dropping it would hide that write until
    // something else touched the table.
    let stream = database.observeConnections()
    observationTask = Task { [weak self] in
      do {
        for try await records in stream {
          self?.applyHydrate(records: records)
        }
      } catch {
        Logger.api.error("Server observation terminated: \(error)")
      }
    }
  }

  deinit {
    observationTask?.cancel()
  }

  /// In-memory cache of connection rows.
  ///
  /// Mutators write the DB first, then apply their own change here eagerly so
  /// callers that read back synchronously (e.g. `login` → `setActiveConnection`
  /// → `refreshConnection`) don't race the observer. ``applyHydrate(records:)``
  /// — driven by the bootstrap read at init and by the `ValueObservation` task
  /// that follows it — is authoritative and reconciles this dict against the
  /// table; being equality-guarded, it is a no-op when the eager write already
  /// matched.
  public private(set) var connections: [UUID: StoredConnection] = [:]

  /// Active server pointer.
  ///
  /// Stays in app-group `UserDefaults` rather than moving into the DB so the
  /// Share Extension picks up active-server changes through UserDefaults' free
  /// cross-process syncing. The "dangling pointer after row delete" case is
  /// handled in ``applyHydrate(records:)`` and ``logout(animated:)``.
  ///
  /// A property wrapper cannot sit on an `@Observable`-tracked property at all:
  /// the macro rewrites `x` into computed accessors over generated storage named
  /// `_x`, which collides with the wrapper's own `_x` and fails to compile with
  /// *"ambiguous reference to member '_x'"*. So the wrapper keeps the storage,
  /// `@ObservationIgnored` keeps the macro off it, and the public property is
  /// hand-written using the same `access` / `withMutation` pair the macro would
  /// have generated.
  ///
  /// Note the key path is the **public** ``activeConnectionId``, not the private
  /// storage: the registrar has to be keyed on what callers actually read, or
  /// observers would never be notified.
  @ObservationIgnored
  @UserDefaultsBacked("ActiveConnectionId", storage: .group)
  private var _activeConnectionId: UUID? = nil

  public var activeConnectionId: UUID? {
    get {
      access(keyPath: \.activeConnectionId)
      return _activeConnectionId
    }
    set {
      withMutation(keyPath: \.activeConnectionId) {
        _activeConnectionId = newValue
      }
    }
  }

  /// Per-connection "needs auth" set. Hydrated from the `needs_auth` column;
  /// kept as a Set<UUID> here so the existing banner / lock-badge
  /// `.onChange(of: needsAuthIds)` watchers keep firing without touching the
  /// SwiftUI sites in this commit.
  public private(set) var needsAuthIds: Set<UUID> = []

  /// Apply a fresh snapshot of records to the in-memory dict and the
  /// needs-auth set. Called by both the bootstrap read and the observer.
  /// Equality-guarded so `objectWillChange` only fires on real changes.
  private func applyHydrate(records: [ConnectionRecord]) {
    var dict: [UUID: StoredConnection] = [:]
    var needsAuth: Set<UUID> = []
    for record in records {
      dict[record.id] = StoredConnection(record: record)
      if record.needsAuth { needsAuth.insert(record.id) }
    }
    if dict != connections { connections = dict }
    if needsAuth != needsAuthIds { needsAuthIds = needsAuth }

    // Dangling-pointer fixup: if a row was deleted (e.g. by logout, or
    // eventually by a cross-process delete after foreground refresh) and
    // the active pointer still names it, advance to whatever else exists
    // or clear. Cheap Swift check — no FK cascade needed.
    if let activeId = activeConnectionId, dict[activeId] == nil {
      activeConnectionId = Self.successor(in: dict)?.id
    }
  }

  /// Which connection to fall back to when the active one disappears.
  ///
  /// Dictionary iteration order isn't stable, so `values.first` would pick a
  /// different server run to run once more than one is configured. Order by
  /// the label the user sees, with the id as a tie-break.
  private static func successor(in dict: [UUID: StoredConnection]) -> StoredConnection? {
    dict.values.min { ($0.label, $0.id.uuidString) < ($1.label, $1.id.uuidString) }
  }

  public func needsAuth(for id: UUID) -> Bool {
    needsAuthIds.contains(id)
  }

  public func markNeedsAuth(for id: UUID) {
    guard !needsAuthIds.contains(id) else { return }
    Logger.api.info(
      "Marking connection \(id, privacy: .private(mask: .hash)) as needing re-authentication")
    do {
      try database.setNeedsAuth(true, forConnection: id)
    } catch {
      Logger.api.error("markNeedsAuth DB write failed: \(error)")
    }
  }

  public func clearNeedsAuth(for id: UUID) {
    guard needsAuthIds.contains(id) else { return }
    Logger.api.info(
      "Clearing needs-auth state for connection \(id, privacy: .private(mask: .hash))")
    do {
      try database.setNeedsAuth(false, forConnection: id)
    } catch {
      Logger.api.error("clearNeedsAuth DB write failed: \(error)")
    }
  }

  // Set by the connection-status banner when the user taps "re-authenticate";
  // the app shell observes this and presents `ReauthSheet`. Decoupled from
  // `needsAuthIds` so the banner can show without auto-presenting a sheet —
  // user consent stays explicit.
  public var reauthRequested: UUID? = nil

  public func requestReauth(for id: UUID) {
    Logger.api.info(
      "Requesting re-auth UI for connection \(id, privacy: .private(mask: .hash))")
    reauthRequested = id
  }

  public func cancelReauthRequest() {
    reauthRequested = nil
  }

  public func setActiveConnection(id: UUID, animated: Bool = true) {
    activeConnectionId = id
    events.emit(.connectionChange(animated: animated))
  }

  public func isServerUnique(_ url: URL) -> Bool {
    let allUrls = connections.values.map(\.url.absoluteString)
    let url = url.absoluteString
    return allUrls.reduce(0) { $1 == url ? $0 + 1 : $0 } == 1
  }

  public var connection: Connection? {
    // @TODO: Downgrade these logs back to debug
    Logger.api.info("Making connection object")

    if previewMode {
      Logger.api.info("Running in preview mode")
      let urlString =
        previewArguments?.url
        ?? "https://paperless.example.com/api/"
      let token =
        previewArguments?.token
        ?? "pseudo-token-that-will-not-work"

      let url = URL(string: urlString)!
      return Connection(
        url: url,
        token: token,
        extraHeaders: [], identityName: nil)
    }

    guard let activeConnectionId, let storedConnection = connections[activeConnectionId] else {
      return nil
    }
    Logger.api.info(
      "Have valid multi-server connection info: \(storedConnection.redactedLabel, privacy: .public)"
    )
    do {
      return try storedConnection.connection
    } catch {
      Logger.api.error(
        "Getting connection from stored connection: \(storedConnection.redactedLabel, privacy: .public)"
      )
      return nil
    }
  }

  public var storedConnection: StoredConnection? {
    if previewMode {
      Logger.api.info("Running in preview mode")

      let urlString =
        previewArguments?.url
        ?? "https://paperless.example.com/api/"
      let url = URL(string: urlString)!

      return StoredConnection(
        url: url,
        extraHeaders: [],
        user: User(id: 1, isSuperUser: true, username: "paperless"))
    }

    guard let activeConnectionId, let stored = connections[activeConnectionId] else {
      return nil
    }
    return stored
  }

  /// Store a connection and make it active.
  ///
  /// Throws if the row can't be persisted. Unlike the other mutators this one
  /// can't just log and carry on: a login that doesn't survive to the next
  /// launch is worse than no login, and the user needs to be told rather than
  /// left looking at a button that did nothing.
  public func login(_ connection: StoredConnection) throws {
    Logger.api.info(
      "Performing login for connection with ID \(connection.id, privacy: .private(mask: .hash))")
    let record = connection.toRecord(needsAuth: needsAuthIds.contains(connection.id))
    try database.upsertConnection(record)
    // Eager, so the upcoming setActiveConnection → connectionChange →
    // refreshConnection sees the row immediately rather than a tick later
    // when the observer fires.
    connections[connection.id] = connection
    setActiveConnection(id: connection.id, animated: false)
  }

  public func setExtraHeaders(_ headers: [Connection.HeaderValue]) {
    guard let activeConnectionId, var stored = connections[activeConnectionId] else {
      Logger.api.warning("Tried to set extra headers but have no active connection (?)")
      return
    }
    Logger.api.trace("Updating extra headers in \(stored.id) to \(headers)")
    stored.extraHeaders = headers
    let record = stored.toRecord(needsAuth: needsAuthIds.contains(stored.id))
    do {
      try database.upsertConnection(record)
    } catch {
      Logger.api.error("setExtraHeaders DB write failed: \(error)")
    }
    // Eager, like every other mutator: the edit takes effect for this session
    // even if it didn't reach disk, rather than the UI silently reverting.
    connections[stored.id] = stored
  }

  /// The active server's offline browsing mode (per-server config). Defaults to
  /// `.recentlyBrowsed` when there's no active connection.
  public var activeOfflineBrowsingMode: OfflineBrowsingMode {
    guard let activeConnectionId, let stored = connections[activeConnectionId] else {
      return .recentlyBrowsed
    }
    return stored.offlineBrowsingMode
  }

  public func setOfflineBrowsingMode(_ mode: OfflineBrowsingMode) {
    guard let activeConnectionId, var stored = connections[activeConnectionId] else {
      Logger.api.warning("Tried to set offline browsing mode but have no active connection")
      return
    }
    let previousMode = stored.offlineBrowsingMode
    guard previousMode != mode else { return }
    Logger.api.info("Updating offline browsing mode on connection \(stored.id) to \(mode.rawValue)")
    stored.offlineBrowsingMode = mode
    // Write through to the in-memory dict immediately so the UI (and the
    // CachingRepository's live record read) see it without waiting for the
    // observeConnections tick.
    connections[activeConnectionId] = stored
    let record = stored.toRecord(needsAuth: needsAuthIds.contains(stored.id))
    var persisted = true
    do {
      try database.upsertConnection(record)
    } catch {
      persisted = false
      Logger.api.error("setOfflineBrowsingMode DB write failed: \(error)")
    }

    // Only reclaim once the new mode is actually on disk. The reclaim is
    // destructive and irreversible; running it after a failed write would gut
    // the cache and then come back at `.entireLibrary` on the next launch,
    // which is the one combination the user can neither see nor undo.
    if persisted, previousMode == .entireLibrary, mode == .recentlyBrowsed {
      runDowngradeGC(serverID: stored.id)
    }
  }

  /// Shrinks the cache back down after a downgrade to `.recentlyBrowsed`.
  /// Turning the mode off doesn't by itself orphan anything — `query_order`
  /// rows persist until something replaces them — so an orphan prune alone
  /// finds nothing to reclaim. `reclaimAfterDowngrade` does the two steps that
  /// make room first (drop every tracked query except the default list, then
  /// cap that list), prunes, and clears the coverage marker, all in one
  /// transaction so a suspended app can't leave the cache half-reclaimed.
  ///
  /// Off the main actor because a server filled at `.entireLibrary` can have a
  /// lot of rows to sweep and this is reached from a Settings picker binding.
  /// `Database` is `Sendable`, so a detached task is enough.
  private func runDowngradeGC(serverID: UUID) {
    let database = database
    Task.detached(priority: .utility) {
      do {
        let removed = try database.reclaimAfterDowngrade(
          serverID: serverID,
          defaultQueryKey: QueryKey(serverID: serverID, filter: .default),
          keepingFirst: OfflineLibrarySize.recentlyBrowsedDefaultListCap)
        Logger.api.info("Downgrade GC removed \(removed) unreferenced documents")
      } catch {
        Logger.api.error("Downgrade GC failed: \(error)")
      }
    }
  }

  public func setFriendlyName(_ name: String?) {
    guard let activeConnectionId, var stored = connections[activeConnectionId] else {
      Logger.api.warning("Tried to set friendly name but have no active connection")
      return
    }
    let normalized = name?.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = (normalized?.isEmpty ?? true) ? nil : normalized
    if stored.friendlyName == value {
      return
    }
    Logger.api.info("Updating friendly name on connection \(stored.id)")
    stored.friendlyName = value
    let record = stored.toRecord(needsAuth: needsAuthIds.contains(stored.id))
    do {
      try database.upsertConnection(record)
    } catch {
      Logger.api.error("setFriendlyName DB write failed: \(error)")
    }
    connections[stored.id] = stored
  }

  public func logout(animated: Bool) {
    Logger.api.info("Requested logout from current server")

    if let activeConnectionId, let storedConnection = connections[activeConnectionId] {
      Logger.api.info("Have active connection \(storedConnection.redactedLabel, privacy: .public)")
      Logger.api.info("Clearing connection with ID \(activeConnectionId)")
      // No clearNeedsAuth() here — it would UPDATE a row this DELETE removes.
      do {
        // Deleting the server row also drops its offline_browsing_mode and
        // cascade-clears its document cache + sync state.
        try database.deleteConnection(id: activeConnectionId)
      } catch {
        Logger.api.error("logout DB delete failed: \(error)")
      }
      connections.removeValue(forKey: activeConnectionId)
      needsAuthIds.remove(activeConnectionId)
      let count = connections.count
      Logger.api.info("Have \(count)")
      if let newConn = Self.successor(in: connections) {
        Logger.api.info("Setting connection to \(newConn.id)")
        setActiveConnection(id: newConn.id, animated: animated)
      } else {
        Logger.api.info("Setting active connection to nil")
        self.activeConnectionId = nil
        events.emit(.logout)
      }
    } else {
      activeConnectionId = nil
      events.emit(.logout)
    }
  }

  /// Debug seam: write the stored connections back out in the pre-database
  /// `UserDefaults` format the v2 migration imports from.
  ///
  /// Without this the database wipe in the corruption-recovery UI can't be
  /// exercised on a build that has only ever stored connections in GRDB —
  /// there is no legacy payload left to restore from, so a wipe just drops
  /// every server. Exporting first makes the wipe a round trip.
  ///
  /// Tokens are untouched; they live in the keychain, not in either store.
  ///
  /// - Returns: how many connections were written.
  @discardableResult
  public func exportConnectionsToLegacyStorage() throws -> Int {
    let count = try database.exportConnectionsToLegacyUserDefaults()
    Logger.api.notice(
      "Exported \(count, privacy: .public) connection(s) to legacy UserDefaults storage")
    return count
  }
}
