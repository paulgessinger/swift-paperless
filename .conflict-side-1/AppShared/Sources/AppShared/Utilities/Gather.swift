//
//  Gather.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.02.23.
//

import Foundation

public func gather<Return: Sendable>(_ functions: (@Sendable () async -> Return)...) async
  -> [Return]
{
  await gather(functions)
}

public func gather(_ functions: (@Sendable () async -> Void)...) async {
  await gather(functions)
}

public func gather<Return: Sendable>(_ functions: [@Sendable () async -> Return]) async -> [Return]
{
  await withTaskGroup(of: Return.self, returning: [Return].self) { g in
    var result: [Return] = []
    for fn in functions {
      g.addTask { await fn() }
    }
    for await r in g {
      result.append(r)
    }
    return result
  }
}

public func gather(_ functions: [@Sendable () async -> Void]) async {
  await withTaskGroup(of: Void.self) { g in
    for fn in functions {
      g.addTask { await fn() }
    }
  }
}
