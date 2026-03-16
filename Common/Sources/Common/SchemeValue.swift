//
//  SchemeValue.swift
//  Common
//
//  Created by Cursor on 15.03.26.
//

import SwiftUI

public struct SchemeToken<Value> {
  public let light: Value
  public let dark: Value

  public init(light: Value, dark: Value) {
    self.light = light
    self.dark = dark
  }
}

@propertyWrapper
public struct SchemeValue<Value>: DynamicProperty {
  @Environment(\.colorScheme)
  private var colorScheme

  private let token: SchemeToken<Value>

  public init(light: Value, dark: Value) {
    token = .init(light: light, dark: dark)
  }

  public init(_ token: SchemeToken<Value>) {
    self.token = token
  }

  public var wrappedValue: Value {
    colorScheme == .light ? token.light : token.dark
  }
}
