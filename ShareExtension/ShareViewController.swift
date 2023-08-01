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
    func didLoadItem(data: NSSecureCoding?, error _: Error?) {
        setLoading(false)
        switch data {
        case let url as URL:
            Logger.shared.debug("Received url \(url)")
            if previewImage == nil {
//                if let preview = pdfPreview(url: url) {
//                    Logger.shared.debug("Have custom pdf render preview")
//                    setPreviewImage(preview)
//                }
//                else {
//                    Task {
//                        // this is on the main actor already anyway
//                        if let image = await makePreviewImage() {
//                            Logger.shared.debug("Have preview image and can set")
//                            setPreviewImage(image)
//                        }
//                    }
//                }
            }
            setDocumentUrl(url)
        default:
            Logger.shared.debug("Got attachment data \(String(describing: data)) but cannot handle")
        }
    }

    func receiveAttachment(attachment: NSItemProvider) {
        guard attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") else {
            Logger.shared.debug("Got invalid attachment")
            self.error = .invalidAttachment
            return
        }

        Logger.shared.trace("Load attach")
        attachment.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil,
                            completionHandler: self.didLoadItem)

        Logger.shared.trace("Load preview")
        attachment.loadPreviewImage(options: [:], completionHandler: { sc, error in
            Logger.shared.trace("Preview completion")
            if error != nil || sc == nil {
                Logger.shared.trace("No preview: error: \(String(describing: error))")
                return
            }

            if let sc = sc {
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

    override func viewDidLoad() {
        super.viewDidLoad()
        Logger.shared.trace("Paperless share extension viewDidLoad fired")

        let shareView = ShareView(attachmentManager: attachmentManager,
                                  callback: {
                                      self.extensionContext!.completeRequest(returningItems: nil, completionHandler: nil)
                                  })

        let childView = UIHostingController(rootView: shareView)
        self.addChild(childView)
        childView.view.frame = self.container.bounds
        self.container.addSubview(childView.view)
        childView.didMove(toParent: self)

        if let item = extensionContext?.inputItems.first as? NSExtensionItem {
            if let attachments = item.attachments {
                for attachment: NSItemProvider in attachments {
                    if attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") {
                        self.attachmentManager.receiveAttachment(attachment: attachment)
                    }
                }
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
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

    var body: some View {
        Group {
            if self.connectionManager.state == .valid {
                if let error = attachmentManager.error {
                    Text(String(describing: error))
                }

                if let url = attachmentManager.documentUrl {
                    VStack {
                        CreateDocumentView(
                            sourceUrl: url,
                            callback: self.callback
                        )
                        // @FIXME: Gives a white band at the bottom, not ideal
                        .padding(.bottom, 40)

                        .environmentObject(self.store)
                        .environmentObject(self.errorController)
                        .accentColor(Color("AccentColor"))
                    }
                }
            }
            else if self.connectionManager.state == .invalid {
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
        .alert(self.error, isPresented: self.$showingError) {
            Button("Ok", role: .cancel) {}
        }

        .task {
            await self.connectionManager.check()
            if let conn = connectionManager.connection {
                self.store.set(repository: ApiRepository(connection: conn))
            }
        }

        .onChange(of: self.attachmentManager.documentUrl) { _ in
//            if let url = url, document.title.isEmpty {
//                document.title = url.lastPathComponent
//            }
        }
    }
}
