//
//  DocumentDetailViewV3.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.07.2024.
//

import Flow
import SwiftUI
import UIKit
import WebKit

private let dragThreshold = 40.0
private let maxDragOffset = 100.0

private struct Aspect<Content: View>: View {
    var label: Content
    var systemImage: String

    @ScaledMetric(relativeTo: .body) private var imageWidth = 20.0
    @ScaledMetric(relativeTo: .body) private var spacing = 5.0

    init(systemImage: String, content: @escaping () -> Content) {
        self.systemImage = systemImage
        label = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            Image(systemName: systemImage)
                .frame(width: imageWidth, alignment: .leading)
                .fontWeight(.medium)
            label
        }
    }
}

private extension Aspect where Content == Text {
    init(_ label: String, systemImage: String) {
        self.label = Text(label)
        self.systemImage = systemImage
    }

    init(_ label: LocalizedStringKey, systemImage: String) {
        self.label = Text(label)
        self.systemImage = systemImage
    }
}

private struct DocumentPropertyView: View {
    @Bindable var viewModel: DocumentDetailModel
    @Binding var showEditSheet: Bool

    @Binding var dragOffset: CGSize

    private var detailOffset: CGFloat {
        max(min(dragOffset.height + 50, 0) * 0.4, -20)
    }

    private var secondaryOffset: CGFloat {
        max(min(dragOffset.height + 50, 0) * 0.2, -10)
    }

    @EnvironmentObject private var store: DocumentStore

    @ScaledMetric(relativeTo: .body) private var spacing = 15.0

    var body: some View {
        let document = viewModel.document
        VStack(alignment: .leading) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if document.title.count < 20 {
                        Text("\(document.title)")
                            .font(.title)
                    } else {
                        Text("\(document.title)")
                            .font(.title2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(y: secondaryOffset)

                Button {
                    Haptics.shared.impact(style: .medium)
                    showEditSheet = true
                } label: {
                    Label(localized: .localizable(.edit), systemImage: "square.and.pencil")
                        .labelStyle(.iconOnly)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .offset(CGSize(width: 0.33, height: -1.33))
                        .padding(8)
                        .background(
                            Circle()
                                .fill(Color.secondary)
                        )
                        .offset(y: -2)
                        .offset(y: secondaryOffset)
                }
            }

            VStack(alignment: .leading) {
                HFlow(itemSpacing: spacing) {
                    if let asn = document.asn {
                        Aspect(String(localized: .localizable(.documentAsn(asn))), systemImage: "qrcode")
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
//                Text("\(chevronSize) \(dragOffset.height)")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .stroke(.tertiary)
            )
            .offset(y: detailOffset)
        }

        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top])
    }
}

@MainActor
struct DocumentDetailViewV3: DocumentDetailViewProtocol {
    @State private var viewModel: DocumentDetailModel
    @State private var webviewOpacity = 0.0
    @State private var topPadding: CGFloat = 0.0
    @State private var bottomPadding: CGFloat = 200

    @State private var showEditSheet = false
    @State private var dragOffset = CGSize.zero

    @Environment(\.dismiss) private var dismiss

    private var chevronSize: CGFloat {
        let y = max(-dragOffset.height, 0)
        return min(1 + y / dragThreshold, 2)
    }

    private var chevronOpacity: CGFloat {
        let y = max(-dragOffset.height, 0)
        return min(1, y / (dragThreshold * 0.9))
    }

    private var chevronOffset: CGFloat {
        let y = max(-dragOffset.height, 0)
        return min(20, 20 * y / dragThreshold)
    }

    init(store: DocumentStore, document: Document, navPath _: Binding<NavigationPath>?) {
        _viewModel = State(initialValue: DocumentDetailModel(store: store,
                                                             document: document))
    }

    var body: some View {
        ZStack {
            if case let .loaded(pdf) = viewModel.download {
                WebView(url: pdf.file, topPadding: $topPadding, bottomPadding: $bottomPadding, load: {
                    webviewOpacity = 1.0
                })
                .equatable()
                .ignoresSafeArea(edges: [.top, .bottom])
                .opacity(webviewOpacity)
            } else {
                ScrollView(.vertical) {
                    ProgressView(label: { Text(.localizable(.loading)) })
                }
            }
        }
        .animation(.default, value: viewModel.download)
        .animation(.default, value: webviewOpacity)
        .safeAreaInset(edge: .bottom) {
            DocumentPropertyView(viewModel: viewModel,
                                 showEditSheet: $showEditSheet,
                                 dragOffset: $dragOffset)
                .padding(.bottom, max(min(50 - dragOffset.height, maxDragOffset), 50))
                .overlay(alignment: .bottom) {
                    Image(systemName: "chevron.up")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 12, height: 12)
                        .opacity(chevronOpacity)
                        .padding(15)
                        .offset(y: -1)
                        .scaleEffect(chevronSize, anchor: .center)
                        .offset(y: -10 - chevronOffset)
                }

                .background(
                    GeometryReader { geo in
                        UnevenRoundedRectangle(topLeadingRadius: 20,
                                               bottomLeadingRadius: 0,
                                               bottomTrailingRadius: 0,
                                               topTrailingRadius: 20,
                                               style: .continuous)
                            .fill(.thinMaterial)
                            .task {
                                let frame = geo.frame(in: .global)
                                bottomPadding = UIScreen.main.bounds.size.height - frame.maxY + frame.height
                            }
                    }
                )

                .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        Haptics.shared.prepare()
                        if dragOffset.height >= -dragThreshold, value.translation.height < -dragThreshold {
                            Haptics.shared.impact(style: .medium)
                        }

                        withAnimation(.interactiveSpring) {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if value.translation.height < -dragThreshold {
                            showEditSheet = true
                        }
                        let velocity = (-value.translation.height < maxDragOffset) ? min(max(-20, value.velocity.height), 0) : 0
                        withAnimation(.interpolatingSpring(initialVelocity: velocity)) {
                            dragOffset = .zero
                        }
                    }
                )
        }

        .ignoresSafeArea(edges: [.top, .bottom])
        .task {
            async let doc: () = viewModel.loadDocument()

            await doc
        }
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(.thinMaterial, for: .navigationBar)

        .sheet(isPresented: $showEditSheet) {
            VStack {
                Text("I am editing")
                Button("Close") {
                    showEditSheet = false
                }
            }
            .presentationDetents(Set(DocumentDetailModel.previewDetents), selection: $viewModel.detent)
            .presentationBackgroundInteraction(
                .enabled(upThrough: .medium)
            )
        }
    }
}

private struct WebView: View, Equatable {
    let url: URL
    @Binding var topPadding: CGFloat
    @Binding var bottomPadding: CGFloat
    let load: (() -> Void)?

    static func == (lhs: WebView, rhs: WebView) -> Bool {
        lhs.url == rhs.url
    }

    var body: some View {
        WebViewInternal(url: url,
                        topPadding: $topPadding,
                        bottomPadding: $bottomPadding,
                        load: load)
    }
}

private struct WebViewInternal: UIViewRepresentable {
    let url: URL
    @Binding var topPadding: CGFloat
    @Binding var bottomPadding: CGFloat

    let load: (() -> Void)?

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewInternal

        let webView: WKWebView

        @MainActor
        init(_ parent: WebViewInternal) {
            self.parent = parent
            webView = WKWebView()
            super.init()
            webView.navigationDelegate = self
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            parent.load?()
        }
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = context.coordinator.webView
        webView.scrollView.contentInset = UIEdgeInsets(top: topPadding, left: 0, bottom: bottomPadding, right: 0)
        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func updateUIView(_: WKWebView, context: Context) {
        let webView = context.coordinator.webView
        print("Update bottom: \(bottomPadding)")
        webView.scrollView.contentInset = UIEdgeInsets(top: topPadding, left: 0, bottom: bottomPadding, right: 0)
    }
}

// MARK: - Previews

private struct PreviewHelper: View {
    @StateObject var store = DocumentStore(repository: PreviewRepository(downloadDelay: 0.0))
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
