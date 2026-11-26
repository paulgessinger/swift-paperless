//
//  LocalEvaluation.swift
//  DataModel
//

import Foundation

/// Describes a document list that was answered on the device, from the cached
/// documents and the stored texts, because the server could not be asked.
///
/// Such a list is the device's best answer, not the server's: it only knows
/// the documents that are cached, it only finds text in the documents whose
/// text is stored, and some parts of a filter can't be applied here at all.
/// This says how far it got, so the list can tell the user what it is showing.
public struct LocalEvaluation: Codable, Sendable, Equatable {
  /// A part of the filter the device could not apply. The list is then wider,
  /// or ordered differently, than the server's would be.
  public enum Limitation: String, Codable, Sendable, CaseIterable {
    /// A custom field query was left out.
    case customFields
    /// The duplicates filter was left out: duplicates are not cached.
    case duplicates
    /// Rules this app has no control for (carried in from a saved view) were
    /// left out.
    case otherRules
    /// An advanced search was reduced to its words; operators and field
    /// prefixes were ignored.
    case advancedSyntax
    /// The sort field isn't available on the device; the list is ordered by
    /// creation date instead.
    case sorting
  }

  public var evaluatedAt: Date

  /// The cached documents the answer was drawn from.
  public var documents: Int

  /// How many of them have their text on the device, when the filter searches
  /// text; `nil` when it doesn't.
  public var documentsWithText: Int?

  public var limitations: [Limitation]

  public init(
    evaluatedAt: Date, documents: Int, documentsWithText: Int? = nil,
    limitations: [Limitation] = []
  ) {
    self.evaluatedAt = evaluatedAt
    self.documents = documents
    self.documentsWithText = documentsWithText
    self.limitations = limitations
  }

  // An unknown limitation, written by a newer build, is dropped rather than
  // failing the whole value.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    evaluatedAt = try container.decode(Date.self, forKey: .evaluatedAt)
    documents = try container.decode(Int.self, forKey: .documents)
    documentsWithText = try container.decodeIfPresent(Int.self, forKey: .documentsWithText)
    limitations = try container.decode([String].self, forKey: .limitations)
      .compactMap(Limitation.init(rawValue:))
  }
}
