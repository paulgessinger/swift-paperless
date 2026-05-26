//
//  FallbackLatch.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.04.26.
//

import Foundation
import os

public struct Attempt<Label: Sendable, Value: Sendable>: Sendable {
  public let label: Label
  public let body: @Sendable () async throws -> Value

  public init(_ label: Label, _ body: @Sendable @escaping () async throws -> Value) {
    self.label = label
    self.body = body
  }

  public static func when(_ label: Label, _ body: @Sendable @escaping () async throws -> Value)
    -> Self
  {
    .init(label, body)
  }
}

@resultBuilder
public enum AttemptsBuilder<Label: Sendable, Value: Sendable> {
  public static func buildBlock(_ parts: Attempt<Label, Value>...) -> [Attempt<Label, Value>] {
    parts
  }
  public static func buildArray(_ parts: [[Attempt<Label, Value>]]) -> [Attempt<Label, Value>] {
    parts.flatMap { $0 }
  }
  public static func buildOptional(_ part: [Attempt<Label, Value>]?) -> [Attempt<Label, Value>] {
    part ?? []
  }
  public static func buildEither(first: [Attempt<Label, Value>]) -> [Attempt<Label, Value>] {
    first
  }
  public static func buildEither(second: [Attempt<Label, Value>]) -> [Attempt<Label, Value>] {
    second
  }
}

public enum FallbackLatchError: Error {
  case noAttempts
  case exhausted(Error)
}

private func describe<L>(_ label: L) -> String {
  "\(type(of: label)).\(label)"
}

public actor FallbackLatch<Label: Sendable & Equatable> {
  private var decided: Label?
  private var deciding: Task<(Label, any Sendable), Error>?

  public init() {}

  public func run<Value: Sendable>(
    _ attempts: [Attempt<Label, Value>],
    fallbackOn: @Sendable @escaping (Error) -> Bool
  ) async throws -> Value {
    guard !attempts.isEmpty else { throw FallbackLatchError.noAttempts }

    if let decided, let hit = attempts.first(where: { $0.label == decided }) {
      Logger.common.debug(
        "FallbackLatch: using latched branch \(describe(decided), privacy: .public)")
      return try await hit.body()
    }

    if let deciding {
      Logger.common.debug("FallbackLatch: awaiting in-flight decider")
      let (label, _) = try await deciding.value
      if let hit = attempts.first(where: { $0.label == label }) {
        Logger.common.debug(
          "FallbackLatch: decider resolved to \(describe(label), privacy: .public), running local body"
        )
        return try await hit.body()
      }
      Logger.common.debug(
        "FallbackLatch: decider resolved to \(describe(label), privacy: .public) but caller didn't offer it, re-probing"
      )
      self.decided = nil
      return try await run(attempts, fallbackOn: fallbackOn)
    }

    Logger.common.debug(
      "FallbackLatch: probing for \(Label.self) \(attempts.count, privacy: .public) attempt(s) in order"
    )

    let t = Task<(Label, any Sendable), Error> {
      var last: Error?
      for attempt in attempts {
        Logger.common.debug(
          "FallbackLatch: trying branch \(describe(attempt.label), privacy: .public)")
        do {
          let v = try await attempt.body()
          Logger.common.debug(
            "FallbackLatch: branch \(describe(attempt.label), privacy: .public) succeeded"
          )
          return (attempt.label, v)
        } catch let error where fallbackOn(error) {
          Logger.common.debug(
            "FallbackLatch: branch \(describe(attempt.label), privacy: .public) failed with a fallback-eligible error; advancing to next branch"
          )
          last = error
          continue
        }
      }
      Logger.common.debug("FallbackLatch: all attempts exhausted")
      throw FallbackLatchError.exhausted(last!)
    }
    deciding = t
    do {
      let (label, boxed) = try await t.value
      Logger.common.debug(
        "FallbackLatch: latched branch \(describe(label), privacy: .public)")
      decided = label
      deciding = nil
      return boxed as! Value
    } catch {
      deciding = nil
      throw error
    }
  }

  public nonisolated func run<Value: Sendable>(
    fallbackOn: @Sendable @escaping (Error) -> Bool,
    @AttemptsBuilder<Label, Value> attempts: @Sendable () -> [Attempt<Label, Value>]
  ) async throws -> Value {
    try await run(attempts(), fallbackOn: fallbackOn)
  }
}
