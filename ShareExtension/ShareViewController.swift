//
//  ShareViewController.swift
//  ShareExtension
//
//  Created by Paul Gessinger on 10.03.23.
//

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
            self.add("\(url)")
            if previewImage == nil {
                if let preview = pdfPreview(url: url) {
                    self.add("have custom pdf render preview")
                    setPreviewImage(preview)
                }
                else {
                    Task {
                        // this is on the main actor already anyway
                        if let image = await makePreviewImage() {
                            setPreviewImage(image)
                        }
                    }
                }
            }
            setDocumentUrl(url)
        default:
            self.add("no clue")
        }
    }

    func receiveAttachment(attachment: NSItemProvider) {
        guard attachment.hasItemConformingToTypeIdentifier("com.adobe.pdf") else {
            NSLog("Got invalid attachment")
            self.error = .invalidAttachment
            return
        }

        self.add("Load attach")
        attachment.loadItem(forTypeIdentifier: "com.adobe.pdf", options: nil,
                            completionHandler: self.didLoadItem)

        self.add("Load preview")
        attachment.loadPreviewImage(options: [:], completionHandler: { sc, error in
            self.add("Preview completion")
            if error != nil || sc == nil {
                self.add("No preview: error: \(String(describing: error))")
                return
            }

            if let sc = sc {
                _ = sc
                fatalError("Got preview, I don't actually know what to do now")
            }

//            guard let sc = sc else {
//                return
//            }
//
//            switch sc {
//            case let data as NSData:
//                self.add("NSData")
//            case let url as NSURL:
//                self.add("NSURL")
//            #if os(iOS)
//                case let image as UIImage:
//                    self.add("UIImage")
//            #elseif os(macOS)
//                case let image as NSImage:
//                    self.add("NSImage")
//            #endif
//            default:
//                self.add("Unknown preview type: \(type(of: sc))")
//            }

        })
    }
}

class ShareViewController: UIViewController {
    @IBOutlet var container: UIView!

    let attachmentManager = AttachmentManager()

    override func viewDidLoad() {
        super.viewDidLoad()

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

    @StateObject private var manager = ConnectionManager()

    @StateObject private var store = DocumentStore(repository: NullRepository())

    var callback: () -> Void

    init(attachmentManager: AttachmentManager, callback: @escaping () -> Void) {
        self.attachmentManager = attachmentManager
        self.callback = callback
    }

    var body: some View {
        Group {
            if manager.state == .valid {
                CreateDocumentView(
                    attachmentManager: attachmentManager,
                    callback: callback
                )
                .environmentObject(store)
                .accentColor(Color("AccentColor"))
            }
            else if manager.state == .invalid {
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
        .task {
            await manager.check()
            if let conn = manager.connection {
                store.set(repository: ApiRepository(connection: conn))
            }
        }
    }
}
