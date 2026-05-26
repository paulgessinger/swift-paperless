//
//  DebounceObject.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import Combine
import Foundation

public class DebounceObject: ObservableObject {
  @Published public var text: String = ""
  @Published public var debouncedText: String = ""
  private var tasks = Set<AnyCancellable>()

  public init(value: String = "", delay: TimeInterval = 0.5) {
    text = value
    $text
      .removeDuplicates()
      .debounce(for: .seconds(delay), scheduler: DispatchQueue.main)
      .sink(receiveValue: { [weak self] value in
        self?.debouncedText = value
      })
      .store(in: &tasks)
  }
}

@MainActor
public final class ThrottleObject<T: Equatable & Sendable>: ObservableObject, Sendable {
  @Published public var value: T
  @Published public var throttledValue: T

  public var publisher = PassthroughSubject<T, Never>()
  private var tasks = Set<AnyCancellable>()

  public init(value: T, delay: TimeInterval = 0.5) {
    self.value = value
    throttledValue = value
    $value
      .throttle(for: .seconds(delay), scheduler: DispatchQueue.main, latest: true)
      .sink(receiveValue: { [weak self] value in
        DispatchQueue.main.async { self?.throttledValue = value }
        self?.publisher.send(value)
      })
      .store(in: &tasks)
  }
}
