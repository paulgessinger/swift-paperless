//
//  QueryFillHandle.swift
//  AppShared
//
//  Opaque result of kicking off a document-list fill (`CachingBackend.fillQuery`).
//  Carries the `QueryKey` the list observes, the server-reported total behind
//  the count pill, and a handle to the background paging task so a refresh /
//  teardown can cancel the in-flight fill. No GRDB crosses this boundary.
//

import Foundation
import Persistence

public struct QueryFillHandle: Sendable {
  /// The key the list view-model subscribes `observeDocumentPrefix` to.
  public let queryKey: QueryKey
  /// Server-reported total from page 1 (the count pill's number), if known.
  public let totalCount: UInt?

  private let fillTask: Task<Void, any Error>

  public init(queryKey: QueryKey, totalCount: UInt?, fillTask: Task<Void, any Error>) {
    self.queryKey = queryKey
    self.totalCount = totalCount
    self.fillTask = fillTask
  }

  /// Cancel the background page-the-rest fill (e.g. on filter change / teardown).
  public func cancel() {
    fillTask.cancel()
  }

  /// Await the background fill completing, rethrowing whatever stopped it early.
  ///
  /// A fill that dies partway — a dropped connection on page 2, the app being
  /// suspended, a newer fill taking the key over — leaves the cached order
  /// truncated. Swallowing that here is what let a caller treat a 250-row order
  /// as the whole 3000-row query, so the error reaches the caller's own
  /// handling instead.
  public func awaitCompletion() async throws {
    try await fillTask.value
  }
}
