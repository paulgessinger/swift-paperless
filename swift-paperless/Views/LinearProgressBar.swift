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

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule()
          .fill(.secondary.opacity(0.15))

        switch mode {
        case .indeterminate:
          ShimmerBar(totalWidth: geo.size.width, height: height)
        case .determinate(let fraction):
          Capsule()
            .fill(.tint)
            .frame(width: max(0, min(1, fraction)) * geo.size.width)
            .animation(.spring(duration: 0.4), value: fraction)
        }
      }
      .frame(width: geo.size.width, height: height)
      .clipped()
    }
    .frame(height: height)
  }
}

private struct ShimmerBar: View {
  let totalWidth: CGFloat
  let height: CGFloat

  @State private var phase: CGFloat = 0

  var body: some View {
    let highlightWidth = totalWidth * 0.55
    let travel = totalWidth + highlightWidth

    Capsule()
      .fill(Color.accentColor.opacity(0.2))
      .frame(width: totalWidth, height: height)
      .overlay(alignment: .leading) {
        LinearGradient(
          stops: [
            .init(color: .clear, location: 0),
            .init(color: Color.accentColor.opacity(0.85), location: 0.5),
            .init(color: .clear, location: 1),
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(width: highlightWidth, height: height)
        .offset(x: phase * travel - highlightWidth)
      }
      .clipShape(Capsule())
      .onAppear {
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
          phase = 1
        }
      }
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
