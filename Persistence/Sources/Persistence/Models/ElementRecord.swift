import Foundation
import GRDB

/// Shared, storage-dedicated JSON coders for element records. Sorted keys give
/// deterministic on-disk output (reproducible dumps in tests/debug exports).
/// Independent of the wire encoder on purpose — storage shape is not API shape.
enum ElementStorage {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }()
  static let decoder = JSONDecoder()
}

/// A GRDB record for one of the per-server element collections.
///
/// Every conformer is a row keyed `(server_id, id)` with a `name` column (for
/// future display/sort) and a `data` JSON column holding the long tail. The
/// `Record ⇄ Domain` mapping lives here in `Persistence` — element domains live
/// in `DataModel`, which `Persistence` already depends on, so (unlike
/// `ConnectionRecord`, whose domain is in `Networking`) no AppShared mapping
/// hop is needed.
public protocol ElementRecord:
  FetchableRecord, PersistableRecord, TableRecord, Codable, Sendable
{
  associatedtype Domain: Sendable
  init(serverId: UUID, domain: Domain)
  var domain: Domain { get }
}

extension ElementRecord {
  public static func databaseJSONEncoder(for column: String) -> JSONEncoder {
    ElementStorage.encoder
  }

  public static func databaseJSONDecoder(for column: String) -> JSONDecoder {
    ElementStorage.decoder
  }
}
