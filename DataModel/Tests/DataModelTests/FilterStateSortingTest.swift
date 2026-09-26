//
//  FilterStateSortingTest.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

/// A field the app default is guaranteed not to be, so "differs from the
/// default" cases hold whatever the store happens to say.
private var fieldOtherThanDefault: SortField {
  FilterState.defaultSorting.field == .title ? .created : .title
}

private func legacyPayload(field: SortField, reverse: Bool) throws -> Data {
  try JSONSerialization.data(
    withJSONObject: ["sortField": field.rawValue, "sortOrder": reverse])
}

@Suite("FilterState sorting")
struct FilterStateSortingTest {
  @Test("A filter that picked no sort resolves to the app default")
  func followsDefault() {
    var state = FilterState.empty
    state.sorting = nil
    #expect(state.resolvedSorting == FilterState.defaultSorting)
  }

  @Test("Writing a sort field pins the sort and keeps the resolved order")
  func writingFieldPins() {
    var state = FilterState.empty
    state.sorting = nil
    let order = state.resolvedSorting.order

    state.sortField = fieldOtherThanDefault

    #expect(state.sorting == FilterState.Sorting(field: fieldOtherThanDefault, order: order))
  }

  @Test("Writing a sort order pins the sort and keeps the resolved field")
  func writingOrderPins() {
    var state = FilterState.empty
    state.sorting = nil
    let field = state.resolvedSorting.field

    state.sortOrder = .ascending

    #expect(state.sorting == FilterState.Sorting(field: field, order: .ascending))
  }

  @Test("A filter that follows the default and one that pins it are the same list")
  func resolvedFormsAgree() {
    var following = FilterState.empty
    following.sorting = nil

    var pinned = FilterState.empty
    pinned.sorting = FilterState.defaultSorting

    #expect(following != pinned)
    #expect(following.resolved == pinned.resolved)
  }

  @Test(
    "Reselecting an ID in a different order is the same list",
    .bug("https://github.com/paulgessinger/swift-paperless/pull/747"))
  func resolvedIgnoresSelectionOrder() {
    let original = FilterState.empty.with {
      $0.tags = .anyOf(ids: [1, 2])
      $0.correspondent = .anyOf(ids: [3, 4])
      $0.documentType = .noneOf(ids: [5, 6])
      $0.storagePath = .anyOf(ids: [7, 8])
      $0.owner = .noneOf(ids: [9, 10])
    }
    let reselected = FilterState.empty.with {
      $0.tags = .anyOf(ids: [2, 1])
      $0.correspondent = .anyOf(ids: [4, 3])
      $0.documentType = .noneOf(ids: [6, 5])
      $0.storagePath = .anyOf(ids: [8, 7])
      $0.owner = .noneOf(ids: [10, 9])
    }

    #expect(original.resolved == reselected.resolved)

    let allOf = FilterState.empty.with { $0.tags = .allOf(include: [1, 2], exclude: [3, 4]) }
    let allOfReselected = FilterState.empty.with {
      $0.tags = .allOf(include: [2, 1], exclude: [4, 3])
    }
    #expect(allOf.resolved == allOfReselected.resolved)
  }

  @Test("Include and exclude stay distinct when canonicalizing tags")
  func resolvedKeepsTagSides() {
    let a = FilterState.empty.with { $0.tags = .allOf(include: [1], exclude: [2]) }
    let b = FilterState.empty.with { $0.tags = .allOf(include: [2], exclude: [1]) }
    #expect(a.resolved != b.resolved)
  }

  @Test("The nullable sort survives a Codable round trip")
  func codableRoundTrip() throws {
    for sorting in [nil, FilterState.Sorting(field: .title, order: .ascending)] {
      var state = FilterState.empty
      state.sorting = sorting

      let decoded = try JSONDecoder().decode(
        FilterState.self, from: JSONEncoder().encode(state))

      #expect(decoded.sorting == sorting)
    }
  }

  @Test("A legacy sort that differs from the default is pinned")
  func legacySortIsPinned() throws {
    let data = try legacyPayload(field: fieldOtherThanDefault, reverse: true)

    var state = FilterState.empty
    state.sorting = nil
    state.adoptLegacySorting(fromPersisted: data)

    #expect(state.sorting == FilterState.Sorting(field: fieldOtherThanDefault, order: .descending))
  }

  @Test("A legacy sort equal to the default goes on following it")
  func legacySortEqualToDefaultKeepsFollowing() throws {
    let `default` = FilterState.defaultSorting
    let data = try legacyPayload(field: `default`.field, reverse: `default`.order.reverse)

    var state = FilterState.empty
    state.sorting = nil
    state.adoptLegacySorting(fromPersisted: data)

    #expect(state.sorting == nil)
  }

  @Test("A filter that already picked a sort is left alone")
  func pinnedSortIsNotOverwritten() throws {
    let data = try legacyPayload(field: fieldOtherThanDefault, reverse: true)

    var state = FilterState.empty
    state.sorting = FilterState.Sorting(field: .owner, order: .ascending)
    state.adoptLegacySorting(fromPersisted: data)

    #expect(state.sorting == FilterState.Sorting(field: .owner, order: .ascending))
  }

  @Test("A payload with no legacy keys leaves the filter following")
  func payloadWithoutLegacyKeys() throws {
    var state = FilterState.empty
    state.sorting = nil
    let data = try JSONEncoder().encode(state)

    state.adoptLegacySorting(fromPersisted: data)

    #expect(state.sorting == nil)
  }
}
