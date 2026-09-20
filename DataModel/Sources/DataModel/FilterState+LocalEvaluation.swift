//
//  FilterState+LocalEvaluation.swift
//  DataModel
//

import Foundation

extension FilterState {
  /// Whether the server would return `document` for this filter, as far as that
  /// can be decided from what is cached — `nil` when it can't be.
  ///
  /// Anchored on the filter's own properties rather than on the query items it
  /// generates: these properties are what the filter UI edits *and* what
  /// ``QueryKey`` is derived from, so an evaluation built on them can't drift
  /// away from either.
  ///
  /// The conditions are combined the way the server applies them — each one
  /// narrows the result independently, i.e. an AND — with a definite rejection
  /// dominating an unevaluable condition: any `false` wins, otherwise any `nil`
  /// wins, otherwise `true`. That order matters: knowing that one condition
  /// rejects the document is enough to know the server won't return it, whether
  /// or not the rest could be evaluated.
  ///
  /// Only the tag conditions are implemented. Every other condition is either
  /// *unset*, and then contributes nothing, or *set*, and then the whole answer
  /// is `nil` — never a guess.
  ///
  /// Notes for whoever extends this:
  ///
  /// - The exact local comparisons, in rough order of how easy they are to get
  ///   right: correspondent, document type, storage path, owner, ASN, and
  ///   absolute created/added date ranges. Each is a field of ``Document``
  ///   compared against ids the filter already holds.
  /// - A *relative* date range (`within N months`, `this year`) is not one of
  ///   them: the server resolves it in its own timezone, so evaluating it here
  ///   silently disagrees with the server around the boundaries. It is a
  ///   divergence trap, not a quick win.
  /// - Full-text search (`text` / `title_search` / `query`), `more_like_id`,
  ///   duplicate detection and custom-field queries are not local questions at
  ///   all: they are answered by the server's search index or by data this app
  ///   doesn't cache.
  /// - Ordering is deliberately out of scope. This answers membership only, so
  ///   it can say a document has left a list, but never where it would be
  ///   inserted into one.
  /// - `nil` reports no reason. A future "what can be filtered offline" UI will
  ///   want the *list* of conditions that couldn't be evaluated rather than a
  ///   single reason, so there is nothing here to extend in the wrong shape.
  public func accepts(_ document: Document) -> Bool? {
    // `sortField`, `sortOrder`, `savedView` and `modified` are not conditions
    // on membership: the first two order the answer, the last two say where
    // the filter came from and whether the user has touched it.
    let conditions: [Bool?] = [
      accepts(tags: document.tags),
      // Exact local comparisons, but not implemented: unset contributes
      // nothing, set is undecidable.
      correspondent == .any ? true : nil,
      documentType == .any ? true : nil,
      storagePath == .any ? true : nil,
      owner == .any ? true : nil,
      asn == .any ? true : nil,
      date.isActive ? nil : true,
      // Answered by the server, not by anything cached here.
      searchText.isEmpty ? true : nil,
      customField == .any ? true : nil,
      // Rules this app doesn't model — including a saved view's `is_in_inbox`,
      // which lands here and is undecidable twice over: it would need to know
      // which tags are inbox tags, and the server only honours the literal
      // `true`/`false` for it, where this app sends `1`/`0`.
      remaining.isEmpty ? true : nil,
    ]

    if conditions.contains(where: { $0 == false }) { return false }
    if conditions.contains(where: { $0 == nil }) { return nil }
    return true
  }

  /// Whether an edit takes `previous` out of this filter's results.
  ///
  /// Two-sided on purpose: the document must have been accepted *before* the
  /// edit and be rejected after it. The first half is what makes this safe to
  /// act on — it says this evaluation agreed with the server about this
  /// document a moment ago, so a rejection now is a change rather than a
  /// disagreement the server was right about all along.
  public func stopsAccepting(previous: Document, updated: Document) -> Bool {
    accepts(previous) == true && accepts(updated) == false
  }

  /// The tag conditions, which are the ones this can answer: the document
  /// carries its own tags, and the server's tag filters are plain set
  /// operations over them.
  private func accepts(tags documentTags: [UInt]) -> Bool {
    let documentTags = Set(documentTags)
    switch tags {
    case .any:
      return true
    case .notAssigned:
      return documentTags.isEmpty
    case .anyOf(let ids):
      // An empty selection sends an empty `tags__id__in`, which the server
      // ignores rather than matching nothing.
      return ids.isEmpty || !documentTags.isDisjoint(with: ids)
    case .allOf(let include, let exclude):
      return include.allSatisfy(documentTags.contains)
        && documentTags.isDisjoint(with: exclude)
    }
  }
}
