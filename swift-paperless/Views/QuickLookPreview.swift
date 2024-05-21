//
//  QuickLookPreview.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.05.2024.
//

import Foundation
import QuickLook
import SwiftUI
import UIKit

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> some UIViewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
//        print(controller.view!)

//        print(controller.contentScrollView(for: .leading))

        return controller
//        let navigationController = UINavigationController(
//            rootViewController: controller
//        )

//        navigationController.navigationBar.isHidden = true
//        navigationController.isNavigationBarHidden = true
//        return navigationController
    }

    func updateUIViewController(_: UIViewControllerType, context _: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: QLPreviewControllerDataSource {
        let parent: QuickLookPreview

        init(parent: QuickLookPreview) {
            self.parent = parent
        }

        func numberOfPreviewItems(in _: QLPreviewController) -> Int {
            1
        }

        func previewController(_: QLPreviewController, previewItemAt _: Int) -> any QLPreviewItem {
            parent.url as NSURL
        }
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
