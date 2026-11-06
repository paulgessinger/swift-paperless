//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 10.03.23.
//

import AppShared
import AppViews
import Social
import SwiftUI
import UIKit
import os

class ShareViewController: UIViewController {
  @IBOutlet var container: UIView!

  let attachmentManager = AttachmentManager()

  var childView: UIViewController? = nil

  override func viewDidLoad() {
    super.viewDidLoad()
    Logger.shared.notice("Paperless share extension viewDidLoad fired")

    let shareView = ShareView(
      attachmentManager: attachmentManager,
      callback: {
        ExtensionDatabaseLifecycle.shared.didDisappear()
        self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
      })

    childView = UIHostingController(rootView: shareView)
    guard let childView else {
      fatalError("Inconsistency")
    }
    addChild(childView)
    container.addSubview(childView.view)
    childView.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      childView.view.topAnchor.constraint(equalTo: container.topAnchor),
      childView.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
      childView.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      childView.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
    ])
    childView.didMove(toParent: self)

    Logger.shared.notice("Receiving shared items")
    if let item = extensionContext?.inputItems.first as? NSExtensionItem {
      if let attachments = item.attachments {
        Logger.shared.debug("Recived item(s): \(attachments)")
        attachmentManager.receive(attachments: attachments)
      } else {
        Logger.shared.warning("Attachment was nil")
      }
    } else {
      Logger.shared.warning("Did not receive any items")
    }
  }

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    ExtensionDatabaseLifecycle.shared.willAppear()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
  }

  // Covers a sheet swiped away, which never reaches `completeRequest`.
  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    ExtensionDatabaseLifecycle.shared.didDisappear()
  }
}
