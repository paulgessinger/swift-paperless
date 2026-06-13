//
//  QueryFillHandle.swift
//  AppShared
//
//  Opaque result of kicking off a document-list fill (`CachingBackend.fillQuery`).
//  Carries the `QueryKey` the list observes, the server-reported total for an
//  exact scrollbar, and a handle to the background paging task so a refresh /
//  teardown can cancel the in-flight fill. No GRDB crosses this boundary.
//

import Foundation
import Persistence

public struct QueryFillHandle: Sendable {
  /// The key the list view-model subscribes `observeDocumentPrefix` to.
  public let queryKey: QueryKey
  /// Server-reported total from page 1 (exact scrollbar extent), if known.
  public let totalCount: UInt?

  private let fillTask: Task<Void, Never>

  public init(queryKey: QueryKey, totalCount: UInt?, fillTask: Task<Void, Never>) {
    self.queryKey = queryKey
    self.totalCount = totalCount
    self.fillTask = fillTask
  }

  /// Cancel the background page-the-rest fill (e.g. on filter change / teardown).
  public func cancel() {
    fillTask.cancel()
  }

  /// Await the background fill completing — primarily for tests and callers that
  /// want the whole view local before proceeding.
  public func awaitCompletion() async {
    await fillTask.value
  }
}
