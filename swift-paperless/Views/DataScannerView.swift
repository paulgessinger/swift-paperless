//
//  DataScannerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.23.
//

import SwiftUI
import UIKit
import VisionKit

struct HighlightView: View {
    var text: String

    private enum Status {
        case loading
        case loaded(document: Document)
        case noAsn
        case invalidAsn(asn: UInt)
    }

    @State private var status = Status.loading

    @EnvironmentObject private var store: DocumentStore

    private var asn: UInt? {
        if let match = try? /(?:ASN)?(\d+)/.wholeMatch(in: text) {
            print(match.1)
            return UInt(match.1)
        }
        return nil
    }

    var body: some View {
//        ZStack {
//            RoundedRectangle(cornerRadius: 15)
//                .fill(.thinMaterial)
//                .scaledToFill()

        HStack {
            switch status {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    if let asn {
                        Text("ASN: \(String(asn))")
                            .fixedSize()
                    }
                }
                .padding()

            case let .loaded(document):
                VStack {
                    //                        Text("ASN: \(String(asn))")
                    //
                    HStack {
                        DocumentPreviewImage(store: store, document: document)
//                                .frame(width: 150)

                        VStack(alignment: .leading) {
                            Text(document.title)
                                .bold()
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(2)
                                .truncationMode(.middle)

                            if let id = document.correspondent, let name = store.correspondents[id]?.name {
                                DocumentCellAspect(name, systemImage: "person")
                                    .foregroundColor(.accentColor)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            if let id = document.documentType, let name = store.documentTypes[id]?.name {
                                DocumentCellAspect(name, systemImage: "doc")
                                    .foregroundColor(Color.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            if let id = document.storagePath, let name = store.storagePaths[id]?.name {
                                DocumentCellAspect(name, systemImage: "archivebox")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            DocumentCellAspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

                            TagsView(tags: document.tags.compactMap { store.tags[$0] })
                                .padding(0)
                        }
//                            .frame(width: 125, alignment: .leading)
                    }
                    .frame(width: 250)
                }
                .id("document_highlight")
                .transition(.identity.combined(with: .opacity).animation(.default.delay(0.2)))

            case .noAsn:
                Text("No ASN: \(text)")
                    .fixedSize()
                    .padding()
            case let .invalidAsn(asn):
                Text("Invalid ASN \(asn)")
                    .fixedSize()
                    .padding()
            }
        }

        .padding(10)

        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(.thinMaterial)
        )

        .task {
//            let document = await store.document(id: 1766)
            guard let asn else {
                status = .noAsn
                return
            }
            guard let document = await store.repository.document(asn: asn) else {
                status = .invalidAsn(asn: asn)
                return
            }

            withAnimation {
                status = .loaded(document: document)
            }
        }

        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 50, maxHeight: .infinity, alignment: .top)
    }
}

struct DataScannerView: UIViewControllerRepresentable {
    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var items: [UUID: UIHostingController<HighlightView>] = [:]

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case let .barcode(code):
                print("BARCODE: \(code)")
            default:
                print("BARCODE: unknown")
            }
        }

//        private func makeHighlightView(bounds: CGRect) -> UIView {
//            let swiftUiView = HighlightView()
//
//            let view = UIHostingController(rootView: swiftUiView)
//            view.view.frame = bounds
//            return view
//        }

        private func centerFromBounds(_ bounds: RecognizedItem.Bounds) -> CGPoint {
            return CGPoint(x: (bounds.bottomLeft.x + bounds.bottomRight.x)/2.0,
                           y: (bounds.bottomLeft.y + bounds.bottomRight.y)/2.0 + 50)
        }

        private func addHighlightView(id: UUID, text: String, center: CGPoint, dataScanner: DataScannerViewController) {
            let vc = UIHostingController(rootView: HighlightView(text: text))
//            vc.view.sizeToFit()
            vc.view.anchorPoint = CGPoint(x: 0.5, y: 1)
            vc.view.center = center
            vc.view.isOpaque = false
            vc.view.backgroundColor = .clear

            items[id] = vc
            dataScanner.addChild(vc)
            vc.didMove(toParent: dataScanner)
            dataScanner.overlayContainerView.addSubview(vc.view)
        }

        private func removeHightlightView(id: UUID) {
            guard let vc = items[id] else { return }
            items.removeValue(forKey: id)
            vc.removeFromParent()
            vc.view.removeFromSuperview()
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case let .barcode(text) = item else {
                    continue
                }
                guard let payload = text.observation.payloadStringValue else {
                    continue
                }

                addHighlightView(id: item.id,
                                 text: payload,
                                 center: centerFromBounds(item.bounds),
                                 dataScanner: dataScanner)
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in updatedItems {
                if let vc = items[item.id] {
                    guard case let .barcode(text) = item else {
                        continue
                    }
                    guard let payload = text.observation.payloadStringValue else {
                        continue
                    }

                    if vc.rootView.text != payload {
                        removeHightlightView(id: item.id)

                        addHighlightView(id: item.id,
                                         text: payload,
                                         center: centerFromBounds(item.bounds),
                                         dataScanner: dataScanner)
                    }
                    else {
                        UIView.animate(withDuration: 0.2) {
                            vc.view.center = self.centerFromBounds(item.bounds)
                        }
                    }
                }
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in removedItems {
                removeHightlightView(id: item.id)
            }
        }
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let viewController = DataScannerViewController(
            recognizedDataTypes: [
                .barcode()
            ],
            qualityLevel: .fast,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: !ProcessInfo.processInfo.isLowPowerModeEnabled,
            isHighlightingEnabled: true
        )

        viewController.delegate = context.coordinator

        try? viewController.startScanning()

        return viewController
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    static var isAvailable: Bool {
        get async {
            let isSupported = await DataScannerViewController.isSupported
            let isAvailable = await DataScannerViewController.isAvailable

            return isSupported && isAvailable
        }
    }
}

struct DataScannerView_Previews: PreviewProvider {
    static var previews: some View {
        DataScannerView()
    }
}
