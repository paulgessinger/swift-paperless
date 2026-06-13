//
//  NamedShareLink.swift
//  AppShared
//

import SwiftUI
import UIKit

/// Identifies a file to be shared along with the display name the share
/// sheet should show ("Save to Files" suggested filename, AirDrop label,
/// etc.). Conforms to `Identifiable` so it can drive `.sheet(item:)`. A
/// fresh `id` per construction means tapping the same file twice in a row
/// re-presents the sheet.
public struct NamedShareItem: Identifiable, Sendable {
  public let id = UUID()
  public let url: URL
  public let name: String

  public init(url: URL, name: String) {
    self.url = url
    self.name = name
  }
}

extension View {
  /// Presents the system share sheet when `item` becomes non-nil, using
  /// `NSItemProvider.suggestedName` so the share sheet shows the
  /// caller-supplied display name instead of the URL's last path component.
  ///
  /// Attach to a view *outside* any `Menu` — SwiftUI menus flatten their
  /// content into UIKit menu items and discard `.sheet` modifiers attached
  /// to those items. The trigger inside the menu is a plain `Button` that
  /// assigns the item; this modifier is what actually drives the sheet.
  public func namedShareSheet(item: Binding<NamedShareItem?>) -> some View {
    sheet(item: item) { item in
      NamedShareSheet(url: item.url, name: item.name)
    }
  }
}

private struct NamedShareSheet: UIViewControllerRepresentable {
  let url: URL
  let name: String

  func makeUIViewController(context _: Context) -> UIActivityViewController {
    let item = stageForShare(canonical: url, name: name) ?? url
    return UIActivityViewController(
      activityItems: [item], applicationActivities: nil)
  }

  func updateUIViewController(_: UIActivityViewController, context _: Context) {}

  /// Stages a hardlink to `canonical` under a fresh UUID-d subdirectory of
  /// `NSTemporaryDirectory()` whose filename matches `name`. The share sheet
  /// then sees a URL whose `lastPathComponent` is the friendly name — which
  /// "Save to Files", AirDrop, and friends all respect (unlike
  /// `NSItemProvider.suggestedName`, which Files specifically ignores).
  ///
  /// Hardlink shares an inode with the canonical blob (no data copy); the
  /// fresh subdirectory means no collision logic; the OS purges
  /// `NSTemporaryDirectory()`, so no cleanup is needed.
  private func stageForShare(canonical: URL, name: String) -> URL? {
    do {
      let subdir = FileManager.default.temporaryDirectory
        .appendingPathComponent(
          "Share-\(UUID().uuidString)", isDirectory: true)
      try FileManager.default.createDirectory(
        at: subdir, withIntermediateDirectories: true)
      let dest = subdir.appendingPathComponent(sanitize(name))
      try FileManager.default.linkItem(at: canonical, to: dest)
      return dest
    } catch {
      return nil
    }
  }

  private func sanitize(_ name: String) -> String {
    let invalid = CharacterSet(charactersIn: "/\0").union(.controlCharacters)
    let scrubbed = name.components(separatedBy: invalid).joined()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return scrubbed.isEmpty ? "document.pdf" : scrubbed
  }
}
