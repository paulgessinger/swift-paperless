//
//  NamedShareLink.swift
//  AppShared
//

import SwiftUI
import UIKit

/// Drop-in alternative to SwiftUI `ShareLink(item: URL)` for file URLs where
/// the on-disk filename and the user-visible name differ. Internally presents
/// `UIActivityViewController` with `NSItemProvider.suggestedName` set to
/// `name`, so the share sheet (Save to Files, Mail, AirDrop, …) shows the
/// human-friendly name without renaming or copying the underlying file.
public struct NamedShareLink<Label: View>: View {
  private let url: URL
  private let name: String
  private let label: () -> Label

  @State private var isPresented = false

  public init(
    url: URL, name: String, @ViewBuilder label: @escaping () -> Label
  ) {
    self.url = url
    self.name = name
    self.label = label
  }

  public var body: some View {
    Button {
      isPresented = true
    } label: {
      label()
    }
    .sheet(isPresented: $isPresented) {
      NamedShareSheet(url: url, name: name)
    }
  }
}

private struct NamedShareSheet: UIViewControllerRepresentable {
  let url: URL
  let name: String

  func makeUIViewController(context _: Context) -> UIActivityViewController {
    let provider = NSItemProvider(contentsOf: url) ?? NSItemProvider()
    provider.suggestedName = name
    return UIActivityViewController(
      activityItems: [provider], applicationActivities: nil)
  }

  func updateUIViewController(_: UIActivityViewController, context _: Context) {}
}
