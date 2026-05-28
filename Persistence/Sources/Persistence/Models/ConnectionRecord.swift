import Foundation
import GRDB

/// GRDB record for a row in the `server` table.
///
/// One row per configured paperless server. Owned end-to-end by `Persistence`:
/// the production write path is `ApiUser → DataModel.User → StoredConnection
/// → ConnectionRecord` (the AppShared layer drives the last step), so
/// `Persistence` never depends on `Networking` or sees wire shapes.
///
/// Two columns carry nested data as JSON: `user` (`StoredUser`) and
/// `extra_headers` (`[StoredHeader]`). They are encoded with the record's own
/// `storageEncoder` / `storageDecoder`, not the wire encoder — storage shape
/// is independent of API shape on purpose.
public struct ConnectionRecord: Equatable, Sendable, Codable {
  public var id: UUID
  public var url: URL
  public var friendlyName: String?
  public var identity: String?
  public var user: StoredUser
  public var extraHeaders: [StoredHeader]
  public var needsAuth: Bool

  public init(
    id: UUID,
    url: URL,
    friendlyName: String? = nil,
    identity: String? = nil,
    user: StoredUser,
    extraHeaders: [StoredHeader] = [],
    needsAuth: Bool = false
  ) {
    self.id = id
    self.url = url
    self.friendlyName = friendlyName
    self.identity = identity
    self.user = user
    self.extraHeaders = extraHeaders
    self.needsAuth = needsAuth
  }

  public struct StoredUser: Codable, Equatable, Sendable {
    public var id: UInt
    public var isSuperUser: Bool
    public var username: String
    public var groups: [UInt]

    public init(id: UInt, isSuperUser: Bool, username: String, groups: [UInt] = []) {
      self.id = id
      self.isSuperUser = isSuperUser
      self.username = username
      self.groups = groups
    }
  }

  public struct StoredHeader: Codable, Equatable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String, value: String) {
      self.id = id
      self.key = key
      self.value = value
    }
  }

  enum CodingKeys: String, CodingKey {
    case id
    case url
    case friendlyName = "friendly_name"
    case identity
    case user
    case extraHeaders = "extra_headers"
    case needsAuth = "needs_auth"
  }
}

// MARK: - GRDB conformances

extension ConnectionRecord: FetchableRecord, PersistableRecord, TableRecord {
  public static let databaseTableName = "server"

  public enum Columns {
    public static let id = Column(CodingKeys.id)
    public static let url = Column(CodingKeys.url)
    public static let friendlyName = Column(CodingKeys.friendlyName)
    public static let identity = Column(CodingKeys.identity)
    public static let user = Column(CodingKeys.user)
    public static let extraHeaders = Column(CodingKeys.extraHeaders)
    public static let needsAuth = Column(CodingKeys.needsAuth)
  }

  // Storage-dedicated JSON coders. Sorted keys for deterministic on-disk
  // output (helps reproducibility of dumps in tests / debug exports).
  // Static so allocations don't recur per record.
  static let storageEncoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
  static let storageDecoder = JSONDecoder()

  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    storageEncoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    storageDecoder
  }
}
