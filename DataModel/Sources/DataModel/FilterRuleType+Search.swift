//
//  FilterRuleType+Search.swift
//  DataModel
//
//  Hand-written companion to the generated `FilterRuleType.swift`.
//

extension FilterRuleType {
  /// Whether this rule type maps to one of the search parameters that
  /// paperless-ngx 3.0 routes through its Tantivy index.
  ///
  /// The backend accepts at most one of `text`, `title_search`, `query` and
  /// `more_like_id` per request and answers with HTTP 400 ("Specify only one
  /// of text, title_search, query, or more_like_id.") otherwise. Before 3.0
  /// only `query` and `more_like_id` went through the search index, and the
  /// remaining ones did not exist, so there was nothing to collide with.
  public var isExclusiveSearchRule: Bool {
    switch self {
    case .simpleText, .simpleTitle, .fulltextQuery, .fulltextMorelike: true
    default: false
    }
  }
}
