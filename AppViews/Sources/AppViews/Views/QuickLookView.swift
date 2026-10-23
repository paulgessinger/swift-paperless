//
//  QuickLookView.swift
//  AppViews
//

import QuickLook
import SwiftUI

/// Embeds QuickLook's preview of a single file, for documents PDFKit can't
/// open. QuickLook picks the viewer from `url`'s extension.
public struct QuickLookView: UIViewControllerRepresentable {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }

  public func makeCoordinator() -> Coordinator {
    Coordinator(url: url)
  }

  public func makeUIViewController(context: Context) -> QLPreviewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    return controller
  }

  public func updateUIViewController(_ controller: QLPreviewController, context: Context) {
    guard context.coordinator.url != url else { return }
    context.coordinator.url = url
    controller.reloadData()
  }

  @MainActor
  public final class Coordinator: NSObject, QLPreviewControllerDataSource {
    var url: URL

    init(url: URL) {
      self.url = url
    }

    public func numberOfPreviewItems(in _: QLPreviewController) -> Int {
      1
    }

    public func previewController(
      _: QLPreviewController, previewItemAt _: Int
    ) -> any QLPreviewItem {
      url as NSURL
    }
  }
}
