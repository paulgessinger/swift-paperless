//
//  DataScannerView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.07.23.
//

import DataModel
import Networking
import os
import SwiftUI
import UIKit
import VisionKit

private func extractAsn(_ value: String, patterns: [Regex<AnyRegexOutput>] = []) -> UInt? {
    let basePattern = /(?:ASN)?(\d+)/
    if let match = try? basePattern.wholeMatch(in: value) {
        return UInt(match.1)
    }

    for pattern in patterns {
        if let match = try? pattern.wholeMatch(in: value) {
            if let mAsn = match.output[1].substring {
                return UInt(mAsn)
            }
        }
    }

    return nil
}

@MainActor
private func makeAsnUrlPattern(store: DocumentStore) -> Regex<AnyRegexOutput>? {
    guard let fullHost = (store.repository as? ApiRepository)?.connection.url else {
        return nil
    }

    let components = URLComponents(url: fullHost, resolvingAgainstBaseURL: false)

    guard let host = components?.host else { return nil }
    let escapedHost = NSRegularExpression.escapedPattern(for: host)

    do {
        return try Regex("^(?:https?:\\/\\/)?\(escapedHost)\\/asn\\/(\\d+)\\/?$")
    } catch {
        Logger.shared.error("Error making expression: \(error)")
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
        case error(error: any Error)
    }

    @State private var status = Status.loading

    var haptics = false

    @EnvironmentObject private var store: DocumentStore

    var asnUrlPattern: [Regex<AnyRegexOutput>] {
        // @TODO: Can I cache this somehow?
        if let pattern = makeAsnUrlPattern(store: store) {
            return [pattern]
        }
        return []
    }

    private var asn: UInt? { extractAsn(text, patterns: asnUrlPattern) }

    var document: Document? {
        switch status {
        case let .loaded(document):
            document
        default:
            nil
        }
    }

    var body: some View {
        HStack {
            switch status {
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    if let asn {
                        Text(.localizable(.asnSpecific(asn)))
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
                Text(.localizable(.dataScannerNoAsn(text)))
                    .fixedSize()
                    .padding()

            case let .invalidAsn(asn):
                Text(.localizable(.dataScannerInvalidAsn(asn)))
                    .fixedSize()
                    .padding()

            case let .error(error):
                Text(error.localizedDescription)
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
            do {
                guard let document = try await store.repository.document(asn: asn) else {
                    if haptics { Haptics.shared.notification(.error) }
                    status = .invalidAsn(asn: asn)
                    return
                }

                if haptics { Haptics.shared.notification(.success) }
                withAnimation {
                    status = .loaded(document: document)
                }

            } catch {
                Logger.shared.error("Error getting document by ASN \(asn): \(error)")
                status = .error(error: error)
                return
            }
        }

        .frame(minWidth: 100, maxWidth: .infinity, minHeight: 50, maxHeight: .infinity, alignment: .top)
    }
}

#if !targetEnvironment(macCatalyst)
    private struct DataScannerViewInternal: UIViewControllerRepresentable {
        var store: DocumentStore
        var isScanning: Binding<Bool>
        var action: ((Document) -> Void)?

        class Coordinator: NSObject, DataScannerViewControllerDelegate {
            let parent: DataScannerViewInternal

            private var items: [UUID: UIHostingController<HighlightView>] = [:]

            init(_ parent: DataScannerViewInternal) {
                self.parent = parent
            }

            func dataScanner(_: DataScannerViewController, didTapOn item: RecognizedItem) {
                guard case let .barcode(text) = item else {
                    Logger.shared.notice("Tapped on none-barcode element")
                    return
                }
                guard let payload = text.observation.payloadStringValue else {
                    Logger.shared.notice("Tapped on element without payload")
                    return
                }

                var patterns: [Regex<AnyRegexOutput>] = []
                if let pattern = makeAsnUrlPattern(store: parent.store) {
                    patterns.append(pattern)
                }

                guard let asn = extractAsn(payload, patterns: patterns) else {
                    Logger.shared.notice("Tapped on element but failed to extract ASN")
                    return
                }

                Task {
                    do {
                        guard let document = try await parent.store.repository.document(asn: asn) else {
                            return
                        }

                        parent.action?(document)
                    } catch {
                        Logger.shared.error("Error getting document by ASN \(asn): \(error)")
                    }
                }
            }

            private func centerFromBounds(_ bounds: RecognizedItem.Bounds) -> CGPoint {
                CGPoint(x: (bounds.bottomLeft.x + bounds.bottomRight.x) / 2.0,
                        y: (bounds.bottomLeft.y + bounds.bottomRight.y) / 2.0 + 50)
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

            func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
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

            func dataScanner(_ dataScanner: DataScannerViewController, didUpdate updatedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
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

            func dataScanner(_: DataScannerViewController, didRemove removedItems: [RecognizedItem], allItems _: [RecognizedItem]) {
                for item in removedItems {
                    removeHightlightView(id: item.id)
                }
            }
        }

        func makeUIViewController(context: Context) -> DataScannerViewController {
            let viewController = DataScannerViewController(
                recognizedDataTypes: [
                    .barcode(),
                ],
                qualityLevel: .fast,
                recognizesMultipleItems: false,
                isHighFrameRateTrackingEnabled: !ProcessInfo.processInfo.isLowPowerModeEnabled,
                isHighlightingEnabled: true
            )

            viewController.delegate = context.coordinator

            if isScanning.wrappedValue {
                try? viewController.startScanning()
            }

            return viewController
        }

        func updateUIViewController(_ uiViewController: DataScannerViewController, context _: Context) {
            if isScanning.wrappedValue {
                try? uiViewController.startScanning()
            } else {
                uiViewController.stopScanning()
            }
        }

        static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator _: Coordinator) {
            uiViewController.stopScanning()
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
    }
#endif

private struct DetailView: View {
    var document: Document

    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DocumentDetailView(store: store, document: document)
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

struct TypeAsnView: View {
    private enum Status {
        case none
        case loading(asn: UInt)
        case valid(document: Document)
        case notAnAsn(asn: String)
        case invalid(asn: UInt)
        case error(error: any Error)
    }

    @State private var text = ""
    @EnvironmentObject private var store: DocumentStore
    @FocusState private var focused: Bool
    @State private var status = Status.none

    @State private var searchTask: Task<Void, Never>?

    var action: (Document) -> Void

    private var asn: UInt? {
        if let _ = try? /\d+/.wholeMatch(in: text) {
            return UInt(text)
        }
        return nil
    }

    private func errorLabel(_ label: String) -> some View {
        Label(label, systemImage: "xmark")
            .labelStyle(.iconOnly)
            .padding(10)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.red)
            )
            .padding(10)
    }

    var body: some View {
        VStack {
            // @TODO: The vertical spacing is kind of wonky. Improve layout
            if case let .valid(document) = status {
                DocumentCell(document: document, store: store)
                    .padding(.top)
                    .padding(.horizontal)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        action(document)
                    }
                    .transition(.identity.combined(with: .opacity).animation(.default.delay(0.1)))

                Divider()
                    .padding(.top, 2)
                    .padding(.bottom, 0)
            }
            HStack {
                Text(.localizable(.asnPlaceholder))
                    .padding(.leading)
                    .padding(.vertical, 19)
                TextField(String("1234"), text: $text)
                    .focused($focused)
                    .keyboardType(.numberPad)
                    .padding(.vertical, 19)

                switch status {
                case .none:
                    EmptyView()
                case .loading:
                    ProgressView()
                        .padding(20)
                case let .valid(document):
                    Button(String(localized: .localizable(.open))) {
                        action(document)
                    }
                    .padding(10)
                    .foregroundColor(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.accentColor)
                    )
                    .padding(10)
                case let .notAnAsn(asn):
                    errorLabel(String(localized: .localizable(.dataScannerNoAsn(asn))))
                case let .invalid(asn):
                    errorLabel(String(localized: .localizable(.dataScannerInvalidAsn(asn))))
                case let .error(error):
                    errorLabel(error.localizedDescription)
                }
            }
        }

        .background(
            //            RoundedRectangle(cornerRadius: 15)
            Rectangle().fill(.thickMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding()
        .onAppear { focused = true }

        .onChange(of: text) {
            searchTask?.cancel()

            searchTask = Task {
                do {
                    try await Task.sleep(for: .seconds(0.5))
                } catch {
                    // should only be cancellation
                    return
                }

                guard !text.isEmpty else {
                    withAnimation { status = .none }
                    return
                }

                guard let asn else {
                    withAnimation {
                        status = .notAnAsn(asn: text)
                    }
                    return
                }

                withAnimation {
                    status = .loading(asn: asn)
                }

                do {
                    if let document = try await store.repository.document(asn: asn) {
                        withAnimation {
                            status = .valid(document: document)
                        }
                    } else {
                        withAnimation {
                            status = .invalid(asn: asn)
                        }
                    }
                } catch {
                    Logger.shared.error("Error getting document by ASN \(asn): \(error)")
                    status = .error(error: error)
                }
            }
        }
    }
}

struct DataScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: DocumentStore

    @State private var document: Document?
    @State private var showTypeAsn = false
    @State private var isScanning = true

    #if !targetEnvironment(macCatalyst)
        var body: some View {
            DataScannerViewInternal(store: store, isScanning: $isScanning) { document in
                self.document = document
            }
            .transaction { t in
                t.animation = nil
            }

            .interactiveDismissDisabled(true)
            .ignoresSafeArea(.container, edges: .bottom)

            .overlay(alignment: .top) {
                HStack {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: .localizable(.cancel)), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .padding(15)
                            .background(Circle().fill(.regularMaterial))
                    }
                    .padding()

                    Spacer()

                    Button {
                        if showTypeAsn {
                            withAnimation {
                                showTypeAsn = false
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(0.5))
                                isScanning = true
                            }
                        } else {
                            isScanning = false
                            withAnimation {
                                showTypeAsn = true
                            }
                        }
                    } label: {
                        Label(String(localized: .localizable(.dataScannerTypeInAsn)), systemImage: "keyboard")
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .padding(15)
                            .background(Circle().fill(.regularMaterial))
                    }
                    .padding()
                }
            }

            .safeAreaInset(edge: .bottom) {
                if showTypeAsn {
                    TypeAsnView { document in
                        self.document = document
                    }
                    .transition(.move(edge: .bottom))
                }
            }

            .sheet(item: $document) { document in
                DetailView(document: document)
            }
        }
    #else
        var body: some View {
            EmptyView()
        }
    #endif

    static var isAvailable: Bool {
        get async {
            #if targetEnvironment(macCatalyst)
                return false
            #else
                let (isSupported, isAvailable) = (DataScannerViewController.isSupported, DataScannerViewController.isAvailable)
                return isSupported && isAvailable
            #endif
        }
    }
}

struct DataScannerView_Previews: PreviewProvider {
    static var previews: some View {
        DataScannerView()
    }
}
