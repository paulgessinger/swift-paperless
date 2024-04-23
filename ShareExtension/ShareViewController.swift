//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 10.03.23.
//

import os
import Social
import SwiftUI
import UIKit

@MainActor private func makePreviewImage() async -> Image? {
    let renderer = ImageRenderer(content:
        ZStack {
            Image(systemName: "doc.text.image")
                .resizable()
                .scaledToFill()
                .padding(10)
            Rectangle()
                .stroke(.white, lineWidth: 3)
                .background(Rectangle().fill(Color.primary))
                .rotationEffect(.degrees(45))
                .frame(width: 7, height: 110)
        }
        .padding(100)
    )
    renderer.scale = 3
    if let uiImage = renderer.uiImage {
        return .init(uiImage: uiImage)
    }
    return nil
}

private extension AttachmentManager {
    @Sendable
    nonisolated func didLoadItem(data: NSSecureCoding?, error _: Error?) {
        Task { @MainActor in
            isLoading = false
        }
        switch data {
        case let url as URL:
            Logger.shared.debug("Received url \(url)")
            Task { @MainActor in
                documentUrl = url
            }
        default:
            Logger.shared.debug("Got attachment data \(String(describing: data)) but cannot handle")
        }
    }

    func receiveAttachment(attachment: NSItemProvider) {
        guard attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") else {
            Logger.shared.debug("Got invalid attachment")
            error = .invalidAttachment
            return
        }

        Logger.shared.notice("Load attach")
        attachment.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil,
                            completionHandler: didLoadItem)

        Logger.shared.notice("Load preview")
        attachment.loadPreviewImage(options: [:], completionHandler: { sc, error in
            Logger.shared.notice("Preview completion")
            if error != nil || sc == nil {
                Logger.shared.notice("No preview: error: \(String(describing: error))")
                return
            }

            if let sc {
                _ = sc
                Logger.shared.error("Got preview, I don't actually know what to do now")
                fatalError("Dead")
            }

        })
    }
}

class ShareViewController: UIViewController {
    @IBOutlet var container: UIView!

    let attachmentManager = AttachmentManager()

    var childView: UIViewController? = nil

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.notice("Paperless share extension viewDidLoad fired")

        let shareView = ShareView(attachmentManager: attachmentManager,
                                  callback: {
                                      self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
                                  })

        childView = UIHostingController(rootView: shareView)
        guard let childView else {
            fatalError("Inconsistency")
        }
        addChild(childView)
        container.addSubview(childView.view)
        childView.didMove(toParent: self)

        if let item = extensionContext?.inputItems.first as? NSExtensionItem {
            if let attachments = item.attachments {
                for attachment: NSItemProvider in attachments {
                    if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                        attachmentManager.receiveAttachment(attachment: attachment)
                    }
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    override public func viewDidLayoutSubviews() {
        // offset is empirical and probably wrong
        let offset: CGFloat
        if traitCollection.horizontalSizeClass == .regular {
            offset = 40
        } else {
            offset = 80
        }
        childView?.view.frame = CGRect(x: container.bounds.origin.x, y: container.bounds.origin.y, width: container.bounds.width, height: container.bounds.height + offset)
    }
}

struct ShareView: View {
    @ObservedObject var attachmentManager: AttachmentManager

    @StateObject private var connectionManager = ConnectionManager()

    @StateObject private var store = DocumentStore(repository: NullRepository())
    @StateObject private var errorController = ErrorController()

    @State private var error: String = ""
    @State private var showingError = false

    var callback: () -> Void

    init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
        self.attachmentManager = attachmentManager
        self.callback = callback
    }

    private func refreshConnection() {
        Logger.api.info("Connection info changed, reloading!")

        if let conn = connectionManager.connection {
            Logger.api.trace("Valid connection from connection manager: \(String(describing: conn))")
            Task {
                store.documentEventPublisher.send(.repositoryWillChange)
                store.set(repository: ApiRepository(connection: conn))
                try? await store.fetchAll()
            }
        } else {
            Logger.shared.trace("App does not have any active connection")
        }
    }

    var body: some View {
        Group {
            if connectionManager.connection != nil {
                if let error = attachmentManager.error {
                    Text(String(describing: error))
                }

                if let url = attachmentManager.documentUrl {
                    VStack {
                        CreateDocumentView(
                            sourceUrl: url,
                            callback: callback,
                            share: true
                        )
                        // @FIXME: Gives a white band at the bottom, not ideal
                        .padding(.bottom, 40)

                        .environmentObject(store)
                        .environmentObject(errorController)
                        .environmentObject(connectionManager)
                        .accentColor(Color("AccentColor"))
                    }
                }
            } else {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Please log in using the app first!")
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    Spacer()
                }
            }
        }
        .alert(error, isPresented: $showingError) {
            Button("Ok", role: .cancel) {}
        }

        .task {
//            await connectionManager.check()
            if let conn = connectionManager.connection {
                store.set(repository: ApiRepository(connection: conn))
            }
        }

        .onChange(of: attachmentManager.documentUrl) { _ in
//            if let url = url, document.title.isEmpty {
//                document.title = url.lastPathComponent
//            }
        }

        .onChange(of: connectionManager.activeConnectionId) { _ in refreshConnection() }
        .onChange(of: connectionManager.connections) { _ in refreshConnection() }
    }
}
