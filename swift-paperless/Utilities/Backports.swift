//
//  Backports.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.12.25.
//
import SwiftUI

public struct Backport<Content> {
  public let content: Content

  public init(_ content: Content) {
    self.content = content
  }
}

extension View {
  public var backport: Backport<Self> { Backport(self) }
}

extension ToolbarContent {
  public var backport: Backport<Self> { Backport(self) }
}

@MainActor
extension Backport where Content: View {

  @ViewBuilder
  public func glassProminentButtonStyle() -> some View {
    glassProminentButtonStyle(or: .borderedProminent)
  }

  @ViewBuilder
  public func glassProminentButtonStyle(or fallback: some PrimitiveButtonStyle) -> some View {
    if #available(iOS 26.0, *) {
      content.buttonStyle(.glassProminent)
    } else {
      content.buttonStyle(fallback)
    }
  }

  @ViewBuilder
  public func glassButtonStyle(or fallback: some PrimitiveButtonStyle = .plain) -> some View {
    if #available(iOS 26.0, *) {
      content.buttonStyle(.glass)
    } else {
      content.buttonStyle(fallback)
    }
  }

  @ViewBuilder
  public func navigationTransitionZoom(sourceID: some Hashable, in namespace: Namespace.ID)
    -> some View
  {
    if #available(iOS 18.0, *) {
      content.navigationTransition(
        .zoom(sourceID: sourceID, in: namespace)
      )
    } else {
      content
    }
  }

  @ViewBuilder
  public func matchedTransitionSource(id: some Hashable, in namespace: Namespace.ID)
    -> some View
  {
    if #available(iOS 18.0, *) {
      content.matchedTransitionSource(id: id, in: namespace)
    } else {
      content
    }
  }
}
