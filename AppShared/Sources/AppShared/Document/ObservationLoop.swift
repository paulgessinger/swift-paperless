//
//  ObservationLoop.swift
//  AppShared
//

import Foundation
import os

/// A loop assigning what `stream` carries to `owner`'s `keyPath`, through
/// `throttle` when there is one. Holds `owner` weakly, so the loop ends with
/// it.
@MainActor
func observationLoop<Owner: AnyObject & Sendable, V: Sendable>(
  _ stream: AsyncThrowingStream<V, Error>,
  into keyPath: ReferenceWritableKeyPath<Owner, V>, of owner: Owner,
  throttle: UpdateThrottle? = nil
) -> Task<Void, Never> {
  Task { @MainActor [weak owner] in
    do {
      for try await value in stream {
        guard let owner else { break }
        guard let throttle else {
          owner[keyPath: keyPath] = value
          continue
        }
        throttle.run { [weak owner] in owner?[keyPath: keyPath] = value }
      }
    } catch is CancellationError {
    } catch {
      Logger.shared.error("\(V.self) observation terminated: \(error)")
    }
  }
}
