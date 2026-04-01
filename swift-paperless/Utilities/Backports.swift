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
  public struct GlassEffectStyle: Sendable {
    private enum Base: Sendable {
      case clear
      case identity
      case regular
    }

    private let base: Base
    private let isInteractive: Bool

    private init(base: Base, isInteractive: Bool = false) {
      self.base = base
      self.isInteractive = isInteractive
    }

    public static var clear: Self { .init(base: .clear) }
    public static var identity: Self { .init(base: .identity) }
    public static var regular: Self { .init(base: .regular) }

    public func interactive() -> Self {
      .init(base: base, isInteractive: true)
    }
  }

  public enum ScrollEdgeEffectStyle: Sendable {
    case hard
    case soft
    case automatic
  }

  public enum ScrollEdge: Sendable {
    case top
    case bottom
  }

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
  public func glassEffect(
    _ style: GlassEffectStyle = .regular,
    in shape: some Shape = Capsule()
  ) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(style.glass, in: shape)
    } else {
      content
    }
  }

  @ViewBuilder
  public func glassEffect<S: ShapeStyle>(
    _ style: GlassEffectStyle = .regular,
    in shape: some Shape = Capsule(),
    orFill: S = Color.clear
  ) -> some View {
    if #available(iOS 26.0, *) {
      content.glassEffect(style.glass, in: shape)
    } else {
      content.background(shape.fill(orFill))
    }
  }

  @ViewBuilder
  public func scrollEdgeEffectStyle(_ style: ScrollEdgeEffectStyle, for edge: ScrollEdge)
    -> some View
  {
    if #available(iOS 26.0, *) {
      content.scrollEdgeEffectStyle(style.scrollEdgeEffectStyle, for: edge.edgeSet)
    } else {
      content
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

@available(iOS 26.0, *)
extension Backport.GlassEffectStyle {
  var glass: Glass {
    let glass: Glass =
      switch base {
      case .clear:
        .clear
      case .identity:
        .identity
      case .regular:
        .regular
      }

    return isInteractive ? glass.interactive() : glass
  }
}

@available(iOS 26.0, *)
extension Backport.ScrollEdgeEffectStyle {
  var scrollEdgeEffectStyle: SwiftUI.ScrollEdgeEffectStyle {
    switch self {
    case .hard:
      .hard
    case .soft:
      .soft
    case .automatic:
      .automatic
    }
  }
}

@available(iOS 26.0, *)
extension Backport.ScrollEdge {
  var edgeSet: Edge.Set {
    switch self {
    case .top:
      .top
    case .bottom:
      .bottom
    }
  }
}

public struct GlassEffectContainerCompat<Content: View>: View {
  @ViewBuilder
  let content: () -> Content

  public var body: some View {
    if #available(iOS 26.0, *) {
      SwiftUI.GlassEffectContainer {
        content()
      }
    } else {
      content()
    }
  }
}
