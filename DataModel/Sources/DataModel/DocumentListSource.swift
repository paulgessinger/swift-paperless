//
//  DocumentListSource.swift
//  DataModel
//

/// A list the app keeps itself, with no server query behind it: read from the
/// local database and never filled.
public enum LocalView: String, Equatable, Codable, Sendable {
  /// The documents the user keeps on the device.
  case keptOffline
}

/// What the document list shows.
public enum DocumentListSource: Equatable, Sendable {
  /// The documents a server query selects.
  case query(FilterState)
  /// A list the app keeps itself.
  case local(LocalView)

  public var localView: LocalView? {
    if case .local(let view) = self { view } else { nil }
  }

  public var filter: FilterState? {
    if case .query(let filter) = self { filter } else { nil }
  }
}
