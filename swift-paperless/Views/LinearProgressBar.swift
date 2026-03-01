import SwiftUI

/// A slim horizontal progress bar with two display modes.
///
/// - `indeterminate`: shows a shimmer sweep to signal ongoing activity.
/// - `determinate(_:)`: fills left-to-right based on a 0–1 fraction.
struct LinearProgressBar: View {
  enum Mode: Equatable {
    case indeterminate
    case determinate(Double)
  }

  var mode: Mode
  var height: CGFloat = 3

  private var isIndeterminate: Bool {
    if case .indeterminate = mode { return true }
    return false
  }

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(.secondary.opacity(0.15))

        switch mode {
        case .indeterminate:
          ShimmerBar(totalWidth: geo.size.width, height: height)
            .transition(.opacity)
        case .determinate(let fraction):
          Capsule()
            .fill(.tint)
            .frame(width: max(0, min(1, fraction)) * geo.size.width)
            .animation(.spring(duration: 0.4), value: fraction)
            .transition(.opacity)
        }
      }
      // Only animate when flipping between the two modes, not on every fraction tick.
      .animation(.easeInOut(duration: 0.25), value: isIndeterminate)
      .frame(width: geo.size.width, height: height)
      .clipped()
    }
    .frame(height: height)
  }
}

// Uses Canvas (Core Graphics) instead of a SwiftUI view hierarchy so there is no
// per-frame view diffing — the main source of shimmer flicker.
private struct ShimmerBar: View {
  let totalWidth: CGFloat
  let height: CGFloat

  private let duration: TimeInterval = 1.2

  var body: some View {
    TimelineView(.animation) { context in
      let phase = CGFloat(
        context.date.timeIntervalSinceReferenceDate
          .truncatingRemainder(dividingBy: duration) / duration
      )

      Canvas { ctx, size in
        let highlightWidth = size.width * 0.55
        let travel = size.width + highlightWidth
        let offsetX = phase * travel - highlightWidth

        let capsule = Path(
          roundedRect: CGRect(origin: .zero, size: size),
          cornerRadius: size.height / 2
        )

        // Base tinted fill.
        ctx.fill(capsule, with: .color(Color.accentColor.opacity(0.2)))

        // Shimmer highlight clipped to the capsule shape.
        var clipped = ctx
        clipped.clip(to: capsule)
        clipped.fill(
          Path(CGRect(x: offsetX, y: 0, width: highlightWidth, height: size.height)),
          with: .linearGradient(
            Gradient(stops: [
              .init(color: .clear, location: 0),
              .init(color: Color.accentColor.opacity(0.85), location: 0.5),
              .init(color: .clear, location: 1),
            ]),
            startPoint: CGPoint(x: offsetX, y: 0),
            endPoint: CGPoint(x: offsetX + highlightWidth, y: 0)
          )
        )
      }
    }
    .frame(width: totalWidth, height: height)
  }
}

#Preview("Indeterminate") {
  LinearProgressBar(mode: .indeterminate)
    .padding()
}

#Preview("Determinate") {
  @Previewable @State var fraction = 0.3

  VStack(spacing: 16) {
    LinearProgressBar(mode: .determinate(fraction))
    Slider(value: $fraction)
  }
  .padding()
}
