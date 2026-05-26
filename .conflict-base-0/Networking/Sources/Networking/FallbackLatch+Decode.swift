//
//  FallbackLatch+Decode.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.04.26.
//

import Common
import Foundation

extension FallbackLatch {
  public nonisolated func decode<Value: Sendable>(
    @AttemptsBuilder<Label, Value> attempts: @Sendable () -> [Attempt<Label, Value>]
  ) async throws -> Value {
    try await run(attempts(), fallbackOn: isShapeMismatch)
  }
}

@Sendable
func isShapeMismatch(_ error: Error) -> Bool {
  let decoding: DecodingError? =
    (error as? DecodingErrorWithRootType)?.error ?? (error as? DecodingError)
  guard let decoding else { return false }
  switch decoding {
  case .keyNotFound, .typeMismatch, .valueNotFound:
    return true
  case .dataCorrupted:
    return false
  @unknown default:
    return false
  }
}
