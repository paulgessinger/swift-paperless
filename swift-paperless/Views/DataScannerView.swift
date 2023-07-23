//
//  DataScannerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.23.
//

import os
import SwiftUI
import UIKit
import VisionKit

private func extractAsn(_ value: String, patterns: [String] = []) -> UInt? {
    let basePattern = /(?:ASN)?(\d+)/
    if let match = try? basePattern.wholeMatch(in: value) {
        return UInt(match.1)
    }

    for pattern in patterns {
        do {
            let ex = try Regex(pattern)
            if let match = try? ex.wholeMatch(in: value) {
                if let mAsn = match.output[1].substring {
                    return UInt(mAsn)
                }
            }
        } catch {
            Logger.shared.error("Invalid pattern supplied to `extractAsn`: \(pattern) -> \(error)")
        }
    }

    return nil
}

struct HighlightView: View {
    var text: String

    private enum Status {
        case loading
        case loaded(document: Document)
        case noAsn
        case invalidAsn(asn: UInt)
    }

    @State private var status = Status.loading

    var haptics = false

    @EnvironmentObject private var store: DocumentStore

    private var asn: UInt? { extractAsn(text) }

    var document: Document? {
        print("DOCUMENT STATUS: \(status)")
        switch status {
        case let .loaded(document):
            return document
        default:
            return nil
        }
    }

    var body: some View {
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
                    HStack {
                        DocumentPreviewImage(store: store, document: document)
                            .frame(height: 200)

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
            if haptics { Haptics.shared.prepare() }
            guard let asn else {
                if haptics { Haptics.shared.notification(.warning) }
                status = .noAsn
                return
            }
            guard let document = await store.repository.document(asn: asn) else {
                if haptics { Haptics.shared.notification(.error) }
                status = .invalidAsn(asn: asn)
                return
            }

            if haptics { Haptics.shared.notification(.success) }
            withAnimation {
                status = .loaded(document: document)
            }
        }

        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 50, maxHeight: .infinity, alignment: .top)
    }
}

private struct DataScannerViewInternal: UIViewControllerRepresentable {
    var store: DocumentStore
    var action: ((Document) -> Void)?

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: DataScannerViewInternal

        private var items: [UUID: UIHostingController<HighlightView>] = [:]

        init(_ parent: DataScannerViewInternal) {
            self.parent = parent
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case let .barcode(text) = item else {
                Logger.shared.trace("Tapped on none-barcode element")
                return
            }
            guard let payload = text.observation.payloadStringValue else {
                Logger.shared.trace("Tapped on element without payload")
                return
            }
            guard let asn = extractAsn(payload) else {
                Logger.shared.trace("Tapped on element but failed to extract ASN")
                return
            }

            Task {
                guard let document = await parent.store.repository.document(asn: asn) else {
                    return
                }

                parent.action?(document)
            }

//            guard let vc = items[item.id] else {
//                Logger.shared.debug("Tapped on item we didn't have a view for")
//                return
//            }
//
//            guard let document = vc.rootView.document else {
//                Logger.shared.trace("Tapped on item which didn't have a document")
//                // no document behind view, so probably invalid code or invalid ASN
//                return
//            }
//
//            parent.action?(document)
        }

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
                    } else {
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
        Coordinator(self)
    }
}

struct DataScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: DocumentStore

    @State private var document: Document?

    private struct DetailView: View {
        var document: Document

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                DocumentDetailView(document: document)
                    .navigationBarTitleDisplayMode(.inline)

                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Back") {
                                dismiss()
                            }
                        }
                    }
            }
        }
    }

    var body: some View {
        DataScannerViewInternal(store: store) { document in
            self.document = document
        }

        .interactiveDismissDisabled(true)
        .ignoresSafeArea(.container, edges: .bottom)

        .overlay(alignment: .topLeading) {
            Button(role: .cancel) {
                dismiss()
            } label: {
                Text("Cancel")
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 15).fill(.regularMaterial))
            }
            .padding()
        }

        .sheet(unwrapping: $document) { document in
            DetailView(document: document.wrappedValue)
        }

//            .safeAreaInset(edge: .top, spacing: 0) {
//                HStack {
//                    Button("Cancel") {
//                        dismiss()
//                    }
//                    Spacer()
//                    Text("Scan ASN")
//                    Spacer()
//                }
//                .padding()
//                .frame(maxWidth: .infinity)
//
//                .background(
//                    Rectangle()
//                        .fill(Material.bar)
//                        .ignoresSafeArea(.container, edges: .top)
//                )
//            }
    }

    static var isAvailable: Bool {
        let isSupported = DataScannerViewController.isSupported
        let isAvailable = DataScannerViewController.isAvailable

        return isSupported && isAvailable
    }
}

struct DataScannerView_Previews: PreviewProvider {
    static var previews: some View {
        DataScannerView()
    }
}
