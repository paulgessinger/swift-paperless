//
//  SyncStepList.swift
//  AppViews
//
//  A sync pass as a headline over its steps, each pending, running or done.
//  It changes height as steps start and finish, which a `List` row does not
//  animate; place it in a plain stack.
//

import SwiftUI

/// One step of a sync pass, as displayed.
public struct SyncStepDisplay: Identifiable, Equatable, Sendable {
  public enum State: Equatable, Sendable {
    case pending, running, done
  }

  public let id: String
  public var title: String
  public var state: State
  /// What the step is working on right now; shown while running.
  public var caption: String?
  /// The count beside the caption; shown while running.
  public var count: String?
  /// `0...1`, or `nil` while the total isn't known.
  public var fraction: Double?

  public init(
    id: String, title: String, state: State = .pending, caption: String? = nil,
    count: String? = nil, fraction: Double? = nil
  ) {
    self.id = id
    self.title = title
    self.state = state
    self.caption = caption
    self.count = count
    self.fraction = fraction
  }
}

/// The headline above the steps.
public struct SyncHeadline: Equatable, Sendable {
  public enum Kind: Equatable, Sendable {
    case syncing, upToDate, waiting, paused, idle
  }

  public var kind: Kind
  public var title: String
  public var detail: String?

  public init(kind: Kind, title: String, detail: String? = nil) {
    self.kind = kind
    self.title = title
    self.detail = detail
  }
}

public struct SyncStepList: View {
  let headline: SyncHeadline
  let steps: [SyncStepDisplay]

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .body) private var rowPadding = 12.0

  public init(headline: SyncHeadline, steps: [SyncStepDisplay]) {
    self.headline = headline
    self.steps = steps
  }

  /// Changes whenever the block changes height or swaps an icon. Animate a
  /// container on it to have the content around the block move with it.
  public static func layoutKey(headline: SyncHeadline, steps: [SyncStepDisplay]) -> some Hashable {
    LayoutKey(kind: headline.kind, states: steps.map(\.state))
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      headlineRow
        .padding(.vertical, rowPadding)
      ForEach(steps) { step in
        VStack(alignment: .leading, spacing: 0) {
          Divider()
          SyncStepRow(step: step)
            .padding(.vertical, rowPadding)
        }
        .transition(.opacity)
      }
    }
    .animation(
      reduceMotion ? nil : .snappy(duration: 0.35),
      value: LayoutKey(kind: headline.kind, states: steps.map(\.state)))
  }

  private var headlineRow: some View {
    HStack(spacing: 10) {
      headlineIcon
        .frame(width: 24)
      Text(headline.title)
        .fontWeight(.semibold)
      Spacer(minLength: 8)
      if let detail = headline.detail {
        Text(detail)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .monospacedDigit()
          .contentTransition(.numericText())
          .animation(reduceMotion ? nil : .default, value: detail)
      }
    }
    .accessibilityElement(children: .combine)
  }

  /// The rotating arrows are a view of their own: a repeating effect that is
  /// switched off still finishes its turn, which would spin the symbol that
  /// replaces them.
  private var headlineIcon: some View {
    ZStack {
      if headline.kind == .syncing {
        Image(systemName: headlineSymbol)
          .foregroundStyle(headlineColor)
          .modifier(RotatingSymbol(active: !reduceMotion))
          .transition(.symbolEffect)
      } else {
        Image(systemName: headlineSymbol)
          .foregroundStyle(headlineColor)
          .contentTransition(.symbolEffect(.replace))
          .transition(.symbolEffect)
      }
    }
  }

  private var headlineSymbol: String {
    switch headline.kind {
    case .syncing: "arrow.triangle.2.circlepath"
    case .upToDate: "checkmark.circle.fill"
    case .waiting: "wifi.exclamationmark"
    case .paused: "pause.circle.fill"
    case .idle: "circle.dashed"
    }
  }

  private var headlineColor: AnyShapeStyle {
    switch headline.kind {
    case .syncing, .upToDate: AnyShapeStyle(.tint)
    case .waiting, .paused: AnyShapeStyle(.orange)
    case .idle: AnyShapeStyle(.secondary)
    }
  }
}

private struct LayoutKey: Hashable {
  let kind: SyncHeadline.Kind
  let states: [SyncStepDisplay.State]
}

private struct RotatingSymbol: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content.symbolEffect(.rotate, options: .repeat(.continuous), isActive: active)
    } else {
      content.symbolEffect(.pulse, isActive: active)
    }
  }
}

private struct SyncStepRow: View {
  let step: SyncStepDisplay

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 10) {
        icon
          .frame(width: 24, height: 22)
        Text(step.title)
          .foregroundStyle(step.state == .pending ? .secondary : .primary)
      }
      if step.state == .running {
        VStack(alignment: .leading, spacing: 6) {
          LinearProgressBar(
            mode: step.fraction.map { .determinate($0) } ?? .indeterminate, height: 4)
          HStack(alignment: .firstTextBaseline) {
            // A blank caption keeps the row's height when a step has nothing
            // to name yet.
            Text(step.caption ?? " ")
              .lineLimit(1)
            Spacer(minLength: 8)
            if let count = step.count {
              Text(count)
                .monospacedDigit()
                .fixedSize()
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .padding(.leading, 34)
        .padding(.top, 8)
        .transition(.opacity)
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var icon: some View {
    Image(systemName: symbol)
      .foregroundStyle(step.state == .pending ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
      .modifier(SpinningSymbol(active: step.state == .running && !reduceMotion))
      .contentTransition(.symbolEffect(.replace))
  }

  private var symbol: String {
    switch step.state {
    case .pending: "circle"
    case .running: SpinningSymbol.name
    case .done: "checkmark.circle.fill"
    }
  }
}

/// The running step's symbol and its motion: the system's spinner as a
/// symbol, so it can be replaced by the checkmark in place.
private struct SpinningSymbol: ViewModifier {
  let active: Bool

  static var name: String {
    if #available(iOS 18.0, *) { "progress.indicator" } else { "circle.dotted" }
  }

  func body(content: Content) -> some View {
    if #available(iOS 18.0, *) {
      content.symbolEffect(
        .variableColor.iterative.dimInactiveLayers, options: .repeat(.continuous),
        isActive: active)
    } else {
      content.symbolEffect(.pulse, isActive: active)
    }
  }
}
