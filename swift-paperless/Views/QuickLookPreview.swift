//
//  QuickLookPreview.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.05.2024.
//

import DataModel
import Foundation
@preconcurrency import QuickLook
import SwiftUI
import UIKit

final class QuickLookPreviewCoordinator: NSObject, QLPreviewControllerDataSource,
  @preconcurrency QLPreviewControllerDelegate
{
  let url: URL

  init(url: URL) {
    self.url = url
  }

  func numberOfPreviewItems(in _: QLPreviewController) -> Int {
    1
  }

  func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
    url as NSURL
  }

  func previewController(
    _: QLPreviewController,
    editingModeFor _: any QLPreviewItem
  ) -> QLPreviewItemEditingMode {
    .disabled
  }
}

struct QuickLookPreview: UIViewControllerRepresentable {
  let url: URL
  var title: String? = nil
  var onClose: (() -> Void)? = nil

  func makeUIViewController(context: Context) -> some UIViewController {
    let controller = QLPreviewController()
    controller.dataSource = context.coordinator
    controller.delegate = context.coordinator
    controller.title = title
    controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
      systemItem: .close,
      primaryAction: UIAction { _ in
        onClose?()
      }
    )

    let navigationController = UINavigationController(rootViewController: controller)
    let appearance = UINavigationBarAppearance()
    appearance.configureWithTransparentBackground()
    navigationController.navigationBar.standardAppearance = appearance
    navigationController.navigationBar.scrollEdgeAppearance = appearance
    navigationController.navigationBar.compactAppearance = appearance
    navigationController.navigationBar.prefersLargeTitles = false
    return navigationController
  }

  func updateUIViewController(_ uiViewController: UIViewControllerType, context _: Context) {
    guard let navigationController = uiViewController as? UINavigationController,
      let controller = navigationController.viewControllers.first as? QLPreviewController
    else {
      return
    }
    controller.title = title
  }

  func makeCoordinator() -> QuickLookPreviewCoordinator {
    QuickLookPreviewCoordinator(url: url)
  }
}

struct DocumentQuickLookPreview: View {
  @EnvironmentObject private var store: DocumentStore

  let document: Document

  @State private var file: URL?

  var body: some View {
    VStack {
      if let file {
        QuickLookPreview(url: file)
      }
    }
    .task {
      guard let url = try? await store.repository.download(documentID: document.id) else {
        print("Error loading file")
        return
      }

      file = url
    }
  }
}
