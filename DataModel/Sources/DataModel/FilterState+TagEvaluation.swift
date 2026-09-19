//
//  FilterState+TagEvaluation.swift
//  DataModel
//

import Foundation

extension FilterState {
  /// Whether this filter's tag conditions reject a document carrying `tags`,
  /// judged the way paperless-ngx judges the request this filter produces.
  ///
  /// Only the *tag* parameters are looked at. Every document filter parameter
  /// narrows the result independently of the others (the server applies each
  /// as a further `filter`/`exclude` on the same queryset), so one failing tag
  /// condition is enough to know the document is out, whatever the rest of
  /// the filter says. The converse does not hold: a `false` here says nothing
  /// about whether the document matches — only that its tags don't rule it out.
  ///
  /// This evaluates the generated query parameters, not the ``tags`` property:
  /// a saved view can carry tag rules that land in ``remaining`` instead
  /// (e.g. an `is_tagged` rule next to an "all of" selection), and rules of one
  /// type are merged into a single parameter before they are sent. Reading
  /// what is actually sent keeps the two from drifting apart.
  ///
  /// Anything that can't be decided exactly counts as "not rejected", so a
  /// caller acting on a `true` never acts on a guess:
  ///
  /// - `is_in_inbox` depends on which tags are inbox tags, and the server only
  ///   honours the literal values `true`/`false` for it — which is not what
  ///   this app sends for a boolean rule. It is never evaluated.
  /// - A tag parameter appearing more than once: which occurrence the server
  ///   reads depends on how the URL is assembled.
  /// - A value the server would itself ignore (empty, or not a list of
  ///   integers), mirroring its fallback of leaving the queryset unfiltered.
  public func tagRulesExclude(tags: some Sequence<UInt>) -> Bool {
    // The encoding only affects the text-search parameters, never the tag
    // ones. `.legacy` is also what `QueryKey` hashes, so this reads the same
    // parameters that identify the cached query.
    let items = FilterRule.queryItems(for: rules(for: .legacy))
      .filter { Self.tagParameters.contains($0.name) }

    var seen = Set<String>()
    for item in items where !seen.insert(item.name).inserted {
      return false
    }

    let tags = Set(tags.map { Int($0) })
    for item in items {
      switch item.name {
      case Self.allParameter:
        guard let ids = Self.objectIDs(item.value) else { continue }
        if !ids.allSatisfy(tags.contains) { return true }
      case Self.anyParameter:
        guard let ids = Self.objectIDs(item.value) else { continue }
        if tags.isDisjoint(with: ids) { return true }
      case Self.noneParameter:
        guard let ids = Self.objectIDs(item.value) else { continue }
        if !tags.isDisjoint(with: ids) { return true }
      case Self.isTaggedParameter:
        guard let wantsTagged = Self.boolean(item.value) else { continue }
        if wantsTagged == tags.isEmpty { return true }
      default:
        continue
      }
    }
    return false
  }

  /// Whether changing a document's tags from `old` to `new` takes it out of
  /// this filter's results.
  ///
  /// Requires the old tags to have passed: a document the tag conditions
  /// already rejected can only be in a cached result because the server
  /// disagrees with this evaluation, and then this evaluation has no business
  /// removing it.
  public func tagChangeExcludes(from old: some Sequence<UInt>, to new: some Sequence<UInt>)
    -> Bool
  {
    !tagRulesExclude(tags: old) && tagRulesExclude(tags: new)
  }

  // MARK: - Server semantics

  private static let allParameter = FilterRuleType.hasTagsAll.filterVar()!
  private static let anyParameter = FilterRuleType.hasTagsAny.filterVar()!
  private static let noneParameter = FilterRuleType.doesNotHaveTag.filterVar()!
  private static let isTaggedParameter = FilterRuleType.hasAnyTag.filterVar()!

  private static let tagParameters: Set<String> = [
    allParameter, anyParameter, noneParameter, isTaggedParameter,
  ]

  /// An `ObjectFilter` value as the server parses it: a comma-separated list
  /// of integers. The server ignores an empty value, and one it can't parse
  /// entirely, so both come back `nil`.
  private static func objectIDs(_ value: String?) -> Set<Int>? {
    guard let value, !value.isEmpty else { return nil }
    var ids = Set<Int>()
    for part in value.split(separator: ",", omittingEmptySubsequences: false) {
      guard let id = Int(part.trimmingCharacters(in: .whitespaces)) else { return nil }
      ids.insert(id)
    }
    return ids
  }

  /// django-filter's `BooleanWidget`: case-insensitive `true`/`false`/`1`/`0`,
  /// anything else leaves the parameter unapplied.
  private static func boolean(_ value: String?) -> Bool? {
    switch value?.lowercased() {
    case "1", "true": true
    case "0", "false": false
    default: nil
    }
  }
}
