//
//  DocumentModel+QueryPlacement.swift
//  DataModel
//

import Foundation

extension Document {
  /// Whether replacing `previous` with `self` could move the document within a
  /// cached query's answer, or into or out of it.
  ///
  /// The cached order of a list (`query_order`) is the server's answer to one
  /// filter and sort. When a refresh lands a newer copy of a document, that
  /// order is only still right if nothing the server filtered or sorted on
  /// changed. `modified` is the test: the server bumps it on every edit to a
  /// document, and it is also the only local witness of changes to state the
  /// cache doesn't hold (content, the search index).
  ///
  /// It is a single field rather than a list of the filterable ones, so a
  /// field added to `Document` later can't be missed. What it rules out is
  /// the common false alarm: the changed-documents delta re-fetches a whole
  /// day from its watermark and hands back many documents identical to the
  /// rows already cached.
  ///
  /// A change the server makes without bumping `modified` (deleting a tag or
  /// correspondent, a bulk edit whose file move failed) goes unnoticed here,
  /// but the delta selects by `modified` and mostly never returns it either.
  public func queryPlacementMayDiffer(from previous: Document) -> Bool {
    modified != previous.modified
  }
}
