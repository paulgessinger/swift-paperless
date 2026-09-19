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
  /// changed. This is the test for that.
  ///
  /// **Fields that count**, each because a `FilterState` rule or a `SortField`
  /// can reference it:
  /// - `title` (title, title/content and simple title searches; title sort)
  /// - `asn` (ASN rules; ASN sort)
  /// - `correspondent`, `documentType`, `storagePath` (their rules; sorting by
  ///   their name)
  /// - `tags`, compared as a set (tag rules, including the inbox)
  /// - `created`, `added`, `modified` (date rules; date sorts)
  /// - `owner` and `permissions` (owner rules, "shared by me", and whether the
  ///   user can see the document at all)
  /// - `notes.count` (notes sort)
  /// - `pageCount` (page count sort)
  /// - `customFields` (custom field rules and queries; custom field sorts)
  /// - `originalFileName` (the MIME type rule reads the original file)
  ///
  /// `modified` is on the list because it is sortable and filterable, but it
  /// also matters for a second reason: it is the only local witness of changes
  /// to things the cache doesn't store. Full-text search, "more like this", the
  /// relevance score and the duplicate filter run on server-side state
  /// (content, the search index) that no field here reflects, so a changed
  /// `modified` has to count on its own.
  ///
  /// **Fields that don't**: `archivedFileName`, `versions` and
  /// `setPermissions`. None is a filter or sort, and `versions` in particular
  /// changes without `modified` on older servers.
  ///
  /// In practice any real edit bumps `modified`, so this is mostly true for a
  /// genuinely changed document. What it rules out is the common false alarm:
  /// the changed-documents delta re-fetches a whole day from its watermark and
  /// hands back many documents identical to the rows already cached.
  public func queryPlacementMayDiffer(from previous: Document) -> Bool {
    title != previous.title
      || asn != previous.asn
      || correspondent != previous.correspondent
      || documentType != previous.documentType
      || storagePath != previous.storagePath
      || Set(tags) != Set(previous.tags)
      || created != previous.created
      || added != previous.added
      || modified != previous.modified
      || owner != previous.owner
      || permissions != previous.permissions
      || notes.count != previous.notes.count
      || pageCount != previous.pageCount
      || customFields != previous.customFields
      || originalFileName != previous.originalFileName
  }
}
