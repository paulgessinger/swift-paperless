//
//  ConnectionManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import AuthenticationServices
import Combine
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

  public init(
    id: UUID = .init(),
    url: URL,
    extraHeaders: [Connection.HeaderValue],
    user: User,
    identity: String? = nil,
    friendlyName: String? = nil
  ) {
    self.id = id
    self.url = url
    self.extraHeaders = extraHeaders
    self.user = user
    self.identity = identity
    self.friendlyName = friendlyName
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
public class ConnectionManager: ObservableObject {
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

  public enum Event {
    case connectionChange(animated: Bool)
    case logout
  }

  public var eventPublisher =
    PassthroughSubject<Event, Never>()

  private let previewArguments: PreviewLaunchArguments?
  public let previewMode: Bool

  private let database: Database
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

    // Observer is the SOLE writer of the in-memory dict from here on.
    // A failed DB write leaves the dict untouched (correct), and on success
    // the observer fires within a runloop tick so SwiftUI re-renders.
    let stream = database.observeConnections()
    observationTask = Task { [weak self] in
      do {
        // Drop the initial snapshot — already applied above.
        var iterator = stream.makeAsyncIterator()
        _ = try await iterator.next()
        while let records = try await iterator.next() {
          await MainActor.run { self?.applyHydrate(records: records) }
        }
      } catch {
        Logger.api.error("Server observation terminated: \(error)")
      }
    }
  }

  deinit {
    observationTask?.cancel()
  }

  /// In-memory cache of connection rows. Written ONLY by ``applyHydrate(records:)``,
  /// which is called from the bootstrap read at init and from the
  /// `ValueObservation` task that follows it. Mutators go through the DB and
  /// let the observer hydrate this dict.
  public private(set) var connections: [UUID: StoredConnection] = [:] {
    willSet {
      objectWillChange.send()
    }
  }

  /// Active server pointer.
  ///
  /// Stays in app-group `UserDefaults` rather than moving into the DB so the
  /// Share Extension picks up active-server changes through UserDefaults' free
  /// cross-process syncing. The "dangling pointer after row delete" case is
  /// handled in ``applyHydrate(records:)`` and ``logout(animated:)``.
  @UserDefaultsBacked("ActiveConnectionId", storage: .group)
  public var activeConnectionId: UUID? = nil {
    willSet {
      objectWillChange.send()
    }
  }

  /// Per-connection "needs auth" set. Hydrated from the `needs_auth` column;
  /// kept as a published Set<UUID> here so the existing banner / lock-badge
  /// `.onChange(of: needsAuthIds)` watchers keep firing without touching the
  /// SwiftUI sites in this commit.
  @Published public private(set) var needsAuthIds: Set<UUID> = []

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
      activeConnectionId = dict.values.first?.id
    }
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
  @Published public var reauthRequested: UUID? = nil

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
    eventPublisher.send(.connectionChange(animated: animated))
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

  public func login(_ connection: StoredConnection) {
    Logger.api.info(
      "Performing login for connection with ID \(connection.id, privacy: .private(mask: .hash))")
    let record = connection.toRecord(needsAuth: needsAuthIds.contains(connection.id))
    do {
      try database.upsertConnection(record)
    } catch {
      Logger.api.error("login DB write failed: \(error)")
      return
    }
    // Update the in-memory dict eagerly so the upcoming setActiveConnection
    // → connectionChange → refreshConnection sees the row immediately
    // (the observer also fires in the next tick; equality-guarded so the
    // double-update is a no-op).
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
  }

  public func logout(animated: Bool) {
    Logger.api.info("Requested logout from current server")

    if let activeConnectionId, let storedConnection = connections[activeConnectionId] {
      Logger.api.info("Have active connection \(storedConnection.redactedLabel, privacy: .public)")
      Logger.api.info("Clearing connection with ID \(activeConnectionId)")
      clearNeedsAuth(for: activeConnectionId)
      do {
        try database.deleteConnection(id: activeConnectionId)
      } catch {
        Logger.api.error("logout DB delete failed: \(error)")
      }
      connections.removeValue(forKey: activeConnectionId)
      let count = connections.count
      Logger.api.info("Have \(count)")
      if let newConn = connections.first?.value {
        Logger.api.info("Setting connection to \(newConn.id)")
        setActiveConnection(id: newConn.id, animated: animated)
      } else {
        Logger.api.info("Setting active connection to nil")
        self.activeConnectionId = nil
        eventPublisher.send(.logout)
      }
    } else {
      activeConnectionId = nil
      eventPublisher.send(.logout)
    }
  }
}
