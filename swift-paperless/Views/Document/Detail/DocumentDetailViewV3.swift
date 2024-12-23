//
//  DocumentDetailViewV3.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.07.2024.
//

import DataModel
import Flow
import NukeUI
import os
import SwiftUI
import UIKit
import WebKit

private let dragThresholdUp = 40.0
private let dragThresholdDown = 40.0
private let maxDragOffset = 100.0

private struct Aspect: View {
    var label: String
    var systemImage: String

    @ScaledMetric(relativeTo: .body) private var imageWidth = 20.0
    @ScaledMetric(relativeTo: .body) private var spacing = 5.0

    init(localized: LocalizedStringResource, systemImage: String) {
        label = String(localized: localized)
        self.systemImage = systemImage
    }

    init(_ label: String, systemImage: String) {
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View {
        Label(label, systemImage: systemImage)
    }
}

private struct DocumentPropertyView: View {
    @Bindable var viewModel: DocumentDetailModel
    @Binding var showEditSheet: Bool

    @Binding var dragOffset: CGSize

    @State private var showMetadata = false
    @State private var showNotes = false

    @ScaledMetric(relativeTo: .body) private var infoButtonSize = 20.0

    private var detailOffset: CGFloat {
        max(min(dragOffset.height + 50, 0) * 0.4, -20)
    }

    private var secondaryOffset: CGFloat {
        max(min(dragOffset.height + 50, 0) * 0.2, -10)
    }

    @EnvironmentObject private var store: DocumentStore
    @EnvironmentObject private var errorController: ErrorController

    @ScaledMetric(relativeTo: .body) private var spacing = 15.0

    var body: some View {
        let document = viewModel.document
        VStack(alignment: .leading) {
            HStack(alignment: .top) {
                Group {
                    if document.title.count < 20 {
                        Text("\(document.title)")
                            .font(.title)
                    } else {
                        Text("\(document.title)")
                            .font(.title2)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: secondaryOffset)

                Label(localized: .localizable(.edit), systemImage: "square.and.pencil.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .fontWeight(.bold)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.primary, .tertiary)
                    .offset(y: secondaryOffset)
                    .onTapGesture {
                        Haptics.shared.impact(style: .medium)
                        showEditSheet = true
                    }
                    .accessibilityIdentifier("documentEditButton")
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    HFlow(itemSpacing: spacing) {
                        if let asn = document.asn {
                            Aspect(localized: .localizable(.documentAsn(asn)), systemImage: "qrcode")
                        }

                        if let id = document.correspondent, let name = store.correspondents[id]?.name {
                            Aspect(name, systemImage: "person")
                        }

                        if let id = document.documentType, let name = store.documentTypes[id]?.name {
                            Aspect(name, systemImage: "doc")
                        }

                        Aspect(DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

                        if let id = document.storagePath, let name = store.storagePaths[id]?.name {
                            Aspect(name, systemImage: "archivebox")
                        }
                    }

                    TagsView(tags: document.tags.compactMap { store.tags[$0] })
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button {
                        showMetadata = true
                    } label: {
                        Label(localized: .documentMetadata(.metadata),
                              systemImage: "info.circle")
                    }

                    Button {
                        showNotes = true
                    } label: {
                        Label(localized: .documentMetadata(.notes),
                              systemImage: "note.text")
                    }

                } label: {
                    Label(localized: .localizable(.details), systemImage: "info.circle.fill")
                        .labelStyle(.iconOnly)
                        .fontWeight(.bold)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .tertiary)
                        .font(.system(size: infoButtonSize))
                        .tint(.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(.ultraThinMaterial)
                    .stroke(.tertiary)
            )
            .offset(y: detailOffset)
            .contentShape(RoundedRectangle(cornerRadius: 15))
        }

        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top])
        .sheet(isPresented: $showMetadata) {
            DocumentMetadataView(document: $viewModel.document, metadata: $viewModel.metadata)
                .environmentObject(store)
                .environmentObject(errorController)
        }

        .sheet(isPresented: $showNotes) {
            DocumentNoteView(document: $viewModel.document)
                .environmentObject(store)
                .environmentObject(errorController)
        }
    }
}

@MainActor
struct DocumentDetailViewV3: DocumentDetailViewProtocol {
    @State private var viewModel: DocumentDetailModel
    @State private var webviewOpacity = 0.0
    @State private var topPadding: CGFloat = 0.0
    @State private var bottomPadding: CGFloat = 200

    @State private var bottomInsetFrame = CGRect.zero

    @State private var showEditSheet = false
    @State private var dragOffset = CGSize.zero
    @State private var dragging = false

    @State private var safeAreaInsets = EdgeInsets()
    @State private var shareLinkUrl: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) var horizontalSizeClass

    @State private var editDetent: PresentationDetent = .medium

    @State private var showPropertyBar = AppSettings.shared.showDocumentDetailPropertyBar

    private var defaultEditDetent: PresentationDetent {
        .large
    }

    private var editDetentOptions: Set<PresentationDetent> {
        switch horizontalSizeClass {
        case .compact:
            [.fraction(0.3), .medium, .large]
        default:
            [.large]
        }
    }

    private var chevronSize: CGFloat {
        let y = max(-dragOffset.height, 0)
        return min(1 + y / dragThresholdUp, 2)
    }

    private var chevronOpacity: CGFloat {
        let y = max(-dragOffset.height, 0)
        return min(1, y / (dragThresholdUp * 0.9))
    }

    private var chevronOffset: CGFloat {
        let y = max(-dragOffset.height, 0)
        let m = safeAreaInsets.bottom - 20
        let o = 20.0
        return min(o, o * y / dragThresholdUp) + m
    }

    private var bottomSpacing: CGFloat {
        let bottom = safeAreaInsets.bottom + 20
        return max(min(bottom - dragOffset.height, maxDragOffset), bottom - 100)
    }

    func updateWebkitInset() {
        guard !dragging else { return }

        bottomPadding = UIScreen.main.bounds.size.height - bottomInsetFrame.maxY + bottomInsetFrame.height // + safeAreaInsets.bottom
//        print("updateWebkitInset \(UIScreen.main.bounds.size.height) - \(bottomInsetFrame.maxY) + \(bottomInsetFrame.height) + \(safeAreaInsets.bottom) = \(bottomPadding)")
    }

    init(store: DocumentStore, document: Document, navPath _: Binding<NavigationPath>?) {
        _viewModel = State(initialValue: DocumentDetailModel(store: store,
                                                             document: document))
    }

    private struct LoadingView: View {
        @Bindable var viewModel: DocumentDetailModel

        @StateObject private var image = FetchImage()

        var body: some View {
            ScrollView(.vertical) {
                VStack {
                    if let image = image.image {
                        image
                            .resizable()
                            .scaledToFit()
                            .blur(radius: 10, opaque: true)
                            .shadow(color: Color(white: 0.2, opacity: 0.3), radius: 5)
                            .padding(.horizontal, 8)
                            .padding(.top, 7)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .animation(.spring(duration: 0.3), value: image.image)
            .scrollDisabled(true)
            .overlay {
                VStack {
                    Text(.localizable(.loading))
                        .foregroundStyle(.primary)
                    ProgressView(value: viewModel.downloadProgress, total: 1.0)
                        .frame(width: 100)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.thinMaterial)
                )
                .animation(.spring, value: viewModel.downloadProgress)
            }

            .task {
                do {
                    try image.load(ImageRequest(urlRequest: viewModel.store.repository.thumbnailRequest(document: viewModel.document)))
                } catch {
                    Logger.shared.error("Error loading document thumbnail: \(error)")
                }
            }
        }
    }

    @ViewBuilder
    private var documentPropertyBar: some View {
        DocumentPropertyView(viewModel: viewModel,
                             showEditSheet: $showEditSheet,
                             dragOffset: $dragOffset)
            .padding(.bottom, bottomSpacing)
            .overlay(alignment: .bottom) {
                Image(systemName: "chevron.compact.up")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .opacity(chevronOpacity)
                    .padding(15)
                    .offset(y: -1)
                    .scaleEffect(chevronSize, anchor: .center)
                    .offset(y: -10 - chevronOffset)
            }

//        .frame(maxHeight: showPropertyBar ? .infinity : 20)
            .frame(height: showPropertyBar ? nil : 0, alignment: .top)
            .clipped()

            .background(
                GeometryReader { geo in
                    UnevenRoundedRectangle(topLeadingRadius: 20,
                                           bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0,
                                           topTrailingRadius: 20,
                                           style: .continuous)
                        .fill(.thinMaterial)
                        .shadow(color: Color(white: 0.5, opacity: 0.3), radius: 10)
                        .task {
                            bottomInsetFrame = geo.frame(in: .global)
                            updateWebkitInset()
                        }
                        .onChange(of: geo.size) {
                            bottomInsetFrame = geo.frame(in: .global)
                            updateWebkitInset()
                        }
                }
            )

            .animation(.spring(duration: 0.2), value: showPropertyBar)

            .highPriorityGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged { value in
                    dragging = true
                    Haptics.shared.prepare()
                    if dragOffset.height >= -dragThresholdUp, value.translation.height < -dragThresholdUp {
                        Haptics.shared.impact(style: .medium)
                    }

                    withAnimation(.interactiveSpring) {
                        dragOffset = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.height < -dragThresholdUp {
                        showEditSheet = true
                    }

                    if value.translation.height > dragThresholdDown {
                        showPropertyBar = false
                    }

                    let velocity = (-value.translation.height < maxDragOffset) ? min(max(-20, value.velocity.height), 0) : 0
                    withAnimation(.interpolatingSpring(initialVelocity: velocity)) {
                        dragOffset = .zero
                    }
                    dragging = false
                }
            )
    }

    var body: some View {
        GeometryReader { geoOuter in
            ZStack(alignment: .center) {
                if case let .loaded(url) = viewModel.download {
                    WebView(url: url,
                            topPadding: $topPadding,
                            bottomPadding: $bottomPadding,
                            safeAreaInsets: $safeAreaInsets,
                            load: {
                                webviewOpacity = 1.0
                            },
                            onTap: nil)
                        .equatable()
                        .ignoresSafeArea(edges: [.top, .bottom])
                        .opacity(webviewOpacity)
                } else {
                    // Somewhat hacky way to center progress view + not push it by swiping up
                    LoadingView(viewModel: viewModel)
                }
            }
            .task {
                safeAreaInsets = geoOuter.safeAreaInsets
            }

            .animation(.default, value: viewModel.download)
            .animation(.default, value: webviewOpacity)
            .safeAreaInset(edge: .bottom) { documentPropertyBar }

            .ignoresSafeArea(edges: [.bottom])

            .overlay(alignment: .bottomLeading) {
                VStack {
                    if !showPropertyBar {
                        Button {
                            showPropertyBar = true
                        } label: {
                            Label(localized: .localizable(.showDocumentPropertiesLabel),
                                  systemImage: "inset.filled.bottomthird.square")
                                .labelStyle(.iconOnly)
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundStyle(.primary)
                                .padding(10)
                                .background(
                                    Circle()
                                        .fill(.background.secondary)
                                        .opacity(0.9)
                                )
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 10)
                        .tint(.primary)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.2), value: showPropertyBar)
            }
        }

        .task {
            editDetent = defaultEditDetent

            async let doc: () = viewModel.loadDocument()

            await viewModel.loadMetadata()

            await doc
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.thinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Label(localized: .localizable(.share), systemImage: "square.and.arrow.up")
                    .tint(.accent)
                    .overlay {
                        Menu {
                            // @TODO: Implement share links
//                            Button {
//                            } label: {
//                                Label(localized: .localizable(.shareLink), systemImage: "link")
//                            }

                            // @TODO: Implement app deep links
//                            Button {
//                            } label: {
//                                Label(localized: .localizable(.shareAppLink), systemImage: "arrow.up.forward.app")
//                            }

                            if case let .loaded(url) = viewModel.download {
                                ShareLink(item: url) {
                                    Label(localized: .localizable(.shareSheet), systemImage: "square.and.arrow.up")
                                }
                            }
                        } label: {
                            EmptyView()
                        }
                    }
            }
        }

        .sheet(isPresented: $showEditSheet) {
            editDetent = defaultEditDetent
        } content: {
            DocumentEditView(store: viewModel.store,
                             document: $viewModel.document)
                .presentationDetents(editDetentOptions, selection: $editDetent)
                .presentationBackgroundInteraction(
                    .enabled(upThrough: .medium)
                )
                .presentationContentInteraction(.scrolls)
        }
    }
}

private struct WebView: View, Equatable {
    let url: URL
    @Binding var topPadding: CGFloat
    @Binding var bottomPadding: CGFloat
    @Binding var safeAreaInsets: EdgeInsets
    let load: (() -> Void)?
    let onTap: (() -> Void)?

    @State private var tapTask: Task<Void, Never>?
    private let tapDelay = Duration.seconds(0.25)

    nonisolated
    static func == (lhs: WebView, rhs: WebView) -> Bool {
        lhs.url == rhs.url
    }

    var body: some View {
        WebViewInternal(url: url,
                        topPadding: $topPadding,
                        bottomPadding: $bottomPadding,
                        safeAreaInsets: $safeAreaInsets,
                        tapTask: $tapTask,
                        load: load)
            .simultaneousGesture(
                ExclusiveGesture(
                    LongPressGesture()
                        .onEnded { finished in
                            print("we long pressed \(finished)")
                        },

                    TapGesture()
                        .onEnded {
                            print("tap")
                            if let tapTask {
                                // tap task already pending, we tapped shortly before and a likely now double tapping
                                tapTask.cancel()
                            } else {
                                // no task pending, we're ok to schedule the tap
                                tapTask = Task {
                                    do {
                                        try await Task.sleep(for: tapDelay)
                                        onTap?()
                                    } catch {}
                                    tapTask = nil
                                }
                            }
                        }
                )
            )
    }
}

private struct WebViewInternal: UIViewRepresentable {
    let url: URL
    @Binding var topPadding: CGFloat
    @Binding var bottomPadding: CGFloat
    @Binding var safeAreaInsets: EdgeInsets

    @Binding var tapTask: Task<Void, Never>?

    let load: (() -> Void)?

    @MainActor
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewInternal

        let webView: WKWebView

        init(_ parent: WebViewInternal) {
            self.parent = parent
            webView = WKWebView()
            super.init()
            webView.navigationDelegate = self
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            parent.load?()
        }

        func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == WKNavigationType.linkActivated {
                if let url = navigationAction.request.url {
                    await UIApplication.shared.open(url)
                }
                parent.tapTask?.cancel()
                return .cancel
            }
            return .allow
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.webView
        updateInsets(webView)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    @MainActor
    private func updateInsets(_ webView: WKWebView) {
//        print("Update bottom: \(bottomPadding)")
        let contentInsets = UIEdgeInsets(top: topPadding, left: 0, bottom: bottomPadding, right: 0)
        webView.scrollView.contentInset = contentInsets
        let scrollInsets = UIEdgeInsets(top: topPadding, left: 0,
                                        bottom: max(0, bottomPadding - safeAreaInsets.bottom),
                                        right: 0)
        webView.scrollView.verticalScrollIndicatorInsets = scrollInsets
    }

    func updateUIView(_: WKWebView, context: Context) {
        let webView = context.coordinator.webView
        updateInsets(webView)
    }
}

// MARK: - Previews

private struct PreviewHelper: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository(downloadDelay: 3.0))
    @StateObject var errorController = ErrorController()

    @State var document: Document?
    @State var navPath = NavigationPath()

    var body: some View {
        NavigationStack {
            VStack {
                if let document {
                    DocumentDetailViewV3(store: store, document: document, navPath: $navPath)
                }
            }
            .task {
                document = try? await store.document(id: 1)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {}
                }
            }
        }
        .environmentObject(store)
        .environmentObject(errorController)
        .task {
            try? await store.fetchAll()
        }
    }
}

#Preview("DocumentDetailsView") {
    PreviewHelper()
}
