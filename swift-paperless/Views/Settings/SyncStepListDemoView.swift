//
//  SyncStepListDemoView.swift
//  swift-paperless
//
//  Debug-only: plays a simulated sync pass through `SyncStepList`, to check
//  the animations without a large library. Not localized.
//

import AppViews
import SwiftUI

struct SyncStepListDemoView: View {
  @State private var elapsed: Double = SyncStepListDemoView.end
  @State private var waiting = false
  @State private var player: Task<Void, Never>?

  private static let end: Double = 20.3
  private static let views: [(name: String, count: Int)] = [
    ("All documents", 3000), ("Inbox", 420), ("Taxes 2026", 260), ("Invoices", 900),
    ("Insurance", 150),
  ]

  private struct Step {
    let id: String
    let title: String
    let start: Double
    let duration: Double
    let detail: (Double) -> (caption: String, count: String?, fraction: Double?)
  }

  private static let script: [Step] = [
    Step(id: "elements", title: "Tags and metadata", start: 0, duration: 1.4) { p in
      ("Correspondents, tags, saved views", "\(Int(p * 8)) of 8", p)
    },
    Step(id: "reconcile", title: "Checking for changes", start: 1.4, duration: 5.2) { p in
      guard p >= 0.3 else { return ("Looking for deleted documents", nil, nil) }
      let q = (p - 0.3) / 0.7
      let index = min(views.count - 1, Int(q * Double(views.count)))
      return (views[index].name, "View \(index + 1) of \(views.count)", q)
    },
    Step(id: "lists", title: "Document lists", start: 2.8, duration: 7) { p in
      let total = views.reduce(0) { $0 + $1.count }
      var remaining = Int(p * Double(total))
      var index = 0
      while index < views.count - 1, remaining > views[index].count {
        remaining -= views[index].count
        index += 1
      }
      return (
        "\(views[index].name) · view \(index + 1) of \(views.count)",
        "\(remaining.formatted()) of \(views[index].count.formatted())", p
      )
    },
    Step(id: "details", title: "Document details", start: 9.8, duration: 3.2) { p in
      ("Notes and file info", "\(Int(p * 3000).formatted()) of 3,000", p)
    },
    Step(id: "text", title: "Document text", start: 13, duration: 2.8) { p in
      ("For search while offline", "\(Int(p * 3000).formatted()) of 3,000", p)
    },
    Step(id: "files", title: "Files", start: 15.8, duration: 4.5) { p in
      (
        "\((p * 1.8).formatted(.number.precision(.fractionLength(1)))) GB · 4 downloading",
        "\(Int(p * 3000).formatted()) of 3,000", p
      )
    },
  ]

  private var steps: [SyncStepDisplay] {
    Self.script.enumerated().map { index, step in
      if waiting {
        return SyncStepDisplay(id: step.id, title: step.title, state: index < 2 ? .done : .pending)
      }
      if elapsed < step.start {
        return SyncStepDisplay(id: step.id, title: step.title)
      }
      if elapsed >= step.start + step.duration {
        return SyncStepDisplay(id: step.id, title: step.title, state: .done)
      }
      let detail = step.detail((elapsed - step.start) / step.duration)
      return SyncStepDisplay(
        id: step.id, title: step.title, state: .running, caption: detail.caption,
        count: detail.count, fraction: detail.fraction)
    }
  }

  private var headline: SyncHeadline {
    let done = steps.filter { $0.state == .done }.count
    if waiting {
      return SyncHeadline(
        kind: .waiting, title: "Waiting for Wi-Fi", detail: "\(done) of \(steps.count) steps")
    }
    if done == steps.count {
      return SyncHeadline(kind: .upToDate, title: "Up to date", detail: "Just now")
    }
    return SyncHeadline(kind: .syncing, title: "Syncing", detail: "\(done) of \(steps.count) steps")
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        CustomSection {
          VStack(spacing: 0) {
            SyncStepList(headline: headline, steps: steps)
            Divider()
            CustomSectionRow {
              Button {
                play()
              } label: {
                Label {
                  Text(verbatim: "Sync now")
                } icon: {
                  Image(systemName: "arrow.clockwise")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
              }
            }
          }
        } header: {
          Text(verbatim: "Status")
        }

        CustomSection {
          VStack(spacing: 0) {
            CustomSectionRow {
              Button {
                player?.cancel()
                waiting = true
              } label: {
                Text(verbatim: "Waiting for Wi-Fi")
              }
            }
            Divider()
            CustomSectionRow {
              Button {
                player?.cancel()
                waiting = false
                elapsed = Self.end
              } label: {
                Text(verbatim: "Up to date")
              }
            }
          }
        } header: {
          Text(verbatim: "Resting states")
        }
      }
      .animation(
        .snappy(duration: 0.35), value: SyncStepList.layoutKey(headline: headline, steps: steps))
    }
    .background(Color(uiColor: .systemGroupedBackground))
    .navigationTitle(Text(verbatim: "Sync step list"))
    .navigationBarTitleDisplayMode(.inline)
    .onDisappear { player?.cancel() }
  }

  private func play() {
    player?.cancel()
    waiting = false
    elapsed = 0
    // Updates land at about the cadence the real stages report at.
    player = Task {
      let start = ContinuousClock.now
      while !Task.isCancelled, elapsed < Self.end {
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled else { return }
        let passed = ContinuousClock.now - start
        elapsed = min(
          Self.end,
          Double(passed.components.seconds) + Double(passed.components.attoseconds) / 1e18)
      }
    }
  }
}
