//
//  NamedShareLink.swift
//  AppShared
//

import AppShared
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
    // "Save to Files", AirDrop and friends name the file after the URL;
    // `NSItemProvider.suggestedName` is ignored by Files.
    let item = NamedFileLink.stage(url, as: name) ?? url
    return UIActivityViewController(
      activityItems: [item], applicationActivities: nil)
  }

  func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
