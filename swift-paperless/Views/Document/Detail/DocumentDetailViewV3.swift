//
//  DocumentDetailViewV3.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 20.07.2024.
//

import BezelKit
import DataModel
import Flow
import Networking
import NukeUI
import SwiftUI
import WebKit
import os

private let dragThresholdUp = 40.0
private let dragThresholdDown = 40.0
private let maxDragOffset = 100.0

private struct Aspect: View {
  var label: String?
  var systemImage: String

  @ScaledMetric(relativeTo: .body) private var imageWidth = 20.0
  @ScaledMetric(relativeTo: .body) private var spacing = 5.0

  init(localized: LocalizedStringResource, systemImage: String) {
    label = String(localized: localized)
    self.systemImage = systemImage
  }

  init(_ label: String?, systemImage: String) {
    self.label = label
    self.systemImage = systemImage
  }

  var body: some View {
    Label(label ?? String(localized: .permissions(.private)), systemImage: systemImage)
      .italic(label == nil)
  }
}

private struct ScrollViewFade<Content: View>: View {
  let content: () -> Content

  @State private var offset: Double = 0
  @State private var height: CGFloat = 0

  private func adapt(_ view: some View) -> some View {
    if #available(iOS 18.0, *) {
      return
        view
        .onScrollGeometryChange(
          for: Double.self, of: { geo in geo.contentOffset.y },
          action: {
            _, newValue in
            offset = newValue
          })
    } else {
      return view
    }
  }

  private var showGradient: Bool {
    offset <= 0
  }

  private var gradient: some View {
    VStack {
      if showGradient {
        LinearGradient(
          stops: [
            Gradient.Stop(color: Color.white, location: 0),
            Gradient.Stop(color: Color.clear, location: 1),
          ], startPoint: .top, endPoint: .bottom)
      } else {
        Rectangle().fill(Color.white)
      }
    }
    .animation(.default, value: showGradient)
  }

  var body: some View {
    adapt(
      ScrollView(.vertical) {
        content()
      }
      .scrollIndicators(.hidden)
    )
    .mask(
      gradient
    )
  }
}

#Preview("ScrollViewFade") {
  VStack {
    ScrollViewFade {
      Text(
        """
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        Test I am very long and will therefore overflow and allow previewing the behavior of this component.
        """)
    }
    .frame(maxHeight: 300)

    .padding()
  }
  .background(Color.red)
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

  @State private var panelHeight: CGFloat = 0

  @ViewBuilder
  private var panel: some View {
    let document = viewModel.document

    ScrollView(.vertical) {
      HStack(alignment: .top) {
        VStack(alignment: .leading) {
          HFlow(itemSpacing: spacing) {
            if let asn = document.asn {
              Aspect(localized: .localizable(.documentAsn(asn)), systemImage: "qrcode")
            }

            if let id = document.correspondent {
              Aspect(store.correspondents[id]?.name, systemImage: "person")
            }

            if let pageCount = document.pageCount {
              Aspect(localized: .localizable(.pages(pageCount)), systemImage: "book.pages")
            }

            if let id = document.documentType {
              Aspect(store.documentTypes[id]?.name, systemImage: "doc")
            }

            Aspect(
              DocumentCell.dateFormatter.string(from: document.created), systemImage: "calendar")

            if let id = document.storagePath {
              Aspect(store.storagePaths[id]?.name, systemImage: "archivebox")
            }

            if case .user(let id) = document.owner {
              Aspect(store.users[id]?.username, systemImage: "person.badge.key")
            }
          }

          TagsView(tags: document.tags.compactMap { store.tags[$0] })
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        Menu {
          Button {
            showMetadata = true
          } label: {
            Label(
              localized: .documentMetadata(.metadata),
              systemImage: "info.circle")
          }

          if viewModel.store.permissions.test(.view, for: .note) {
            Button {
              showNotes = true
            } label: {
              Label(
                localized: .documentMetadata(.notes),
                systemImage: "note.text")
            }
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

      .background {
        GeometryReader { geo in
          Color.clear
            .onAppear {
              panelHeight = geo.size.height
            }
            .onChange(of: geo.size) {
              panelHeight = geo.size.height
            }
        }
      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .scrollIndicators(.hidden)
    .frame(height: min(panelHeight, 150))

    .apply {
      if #available(iOS 26.0, *) {
        $0.glassEffect(.clear, in: RoundedRectangle(cornerRadius: 15))
      } else {
        $0.background(
          RoundedRectangle(cornerRadius: 15)
            .fill(.ultraThinMaterial)
            .stroke(.tertiary)
        )
      }
    }

    .offset(y: detailOffset)
    .contentShape(RoundedRectangle(cornerRadius: 15))
  }

  @ViewBuilder
  var documentTitle: some View {
    let document = viewModel.document
    Text("\(document.title)")
      .font(.title2)
  }

  var body: some View {
    let document = viewModel.document
    VStack(alignment: .leading) {
      HStack(alignment: .top) {
        documentTitle
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .fixedSize(horizontal: false, vertical: true)
          .opacity(0)

          .overlay {
            ViewThatFits(in: .vertical) {
              documentTitle
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .topLeading)

              ScrollViewFade {
                Text("\(document.title)")
                  .font(.title)
              }
              .frame(maxWidth: .infinity, alignment: .topLeading)
            }
          }
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

      panel
    }

    .frame(
      maxWidth: .infinity,
      alignment: .topLeading
    )
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
  @Environment(RouteManager.self) private var routeManager

  @State private var bottomInsetFrame = CGRect.zero

  @State private var showEditSheet = false
  @State private var dragOffset = CGSize.zero
  @State private var dragging = false

  @State private var showShareLinkSheet = false

  @State private var safeAreaInsets = EdgeInsets()
  @State private var shareLinkUrl: URL?

  @Environment(\.dismiss) private var dismiss
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.colorScheme) private var colorScheme

  @EnvironmentObject private var errorController: ErrorController

  var navPath: Binding<[NavigationState]>? = nil

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

    bottomPadding =
      UIScreen.main.bounds.size.height - bottomInsetFrame.maxY + bottomInsetFrame.height  // + safeAreaInsets.bottom
    //        print("updateWebkitInset \(UIScreen.main.bounds.size.height) - \(bottomInsetFrame.maxY) + \(bottomInsetFrame.height) + \(safeAreaInsets.bottom) = \(bottomPadding)")
  }

  private func handlePendingRoute() {
    guard let action = routeManager.pendingRoute?.action else { return }
    guard case .document(let docId, let edit) = action else { return }
    guard docId == viewModel.document.id else { return }
    routeManager.pendingRoute = nil
    showEditSheet = edit
  }

  init(
    store: DocumentStore, connection: Connection?, document: Document,
    navPath: Binding<[NavigationState]>?
  ) {
    _viewModel = State(
      initialValue: DocumentDetailModel(
        store: store,
        connection: connection,
        document: document))
    self.navPath = navPath
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

        .apply {
          if #available(iOS 26.0, *) {
            $0
              .padding(.horizontal, 20)
              .glassEffect()
          } else {
            $0.background(
              RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
            )
          }
        }
      }

      .task {
        do {
          try image.load(
            ImageRequest(
              urlRequest: viewModel.store.repository.thumbnailRequest(document: viewModel.document))
          )
        } catch {
          Logger.shared.error("Error loading document thumbnail: \(error)")
        }
      }
    }
  }

  private var concentricBottomRect: UnevenRoundedRectangle {
    UnevenRoundedRectangle(
      topLeadingRadius: 20,
      bottomLeadingRadius: .deviceBezel - 5,
      bottomTrailingRadius: .deviceBezel - 5,
      topTrailingRadius: 20,
      style: .continuous
    )
  }

  @available(iOS 26.0, *)
  @ViewBuilder
  private var liquidGlassBackground: some View {
    if colorScheme == .light {
      concentricBottomRect
        .fill(Color(white: 0.9, opacity: 0.5))
    } else {
      Color.clear
    }
  }

  @ViewBuilder
  private var documentPropertyBar: some View {
    DocumentPropertyView(
      viewModel: viewModel,
      showEditSheet: $showEditSheet,
      dragOffset: $dragOffset
    )
    .padding(.bottom, bottomSpacing)
    .apply {
      if #available(iOS 26.0, *) {
        $0.padding(.top, 5)
          .padding(.horizontal, 5)
      } else {
        $0
      }
    }
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

    .frame(height: showPropertyBar ? nil : 0, alignment: .top)
    .clipped()

    .background(
      GeometryReader { geo in
        Group {
          if #available(iOS 26.0, *) {
            liquidGlassBackground
              .glassEffect(
                colorScheme == .light ? .clear : .regular,
                in:
                  concentricBottomRect
              )
              .padding(5)
          } else {
            UnevenRoundedRectangle(
              topLeadingRadius: 20,
              bottomLeadingRadius: 0,
              bottomTrailingRadius: 0,
              topTrailingRadius: 20,
              style: .continuous
            )
            .fill(.ultraThinMaterial)
            .shadow(color: Color(white: 0.5, opacity: 0.3), radius: 10)
          }
        }
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

  }

  var body: some View {
    GeometryReader { geoOuter in
      ZStack(alignment: .center) {
        if case .loaded(url: let url, document: _) = viewModel.download {
          WebView(
            url: url,
            topPadding: $topPadding,
            bottomPadding: $bottomPadding,
            safeAreaInsets: $safeAreaInsets,
            load: {
              webviewOpacity = 1.0
            },
            onTap: nil
          )
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
              Label(
                localized: .localizable(.showDocumentPropertiesLabel),
                systemImage: "inset.filled.bottomthird.square"
              )
              .labelStyle(.iconOnly)
              .padding(10)
              .apply {
                if #available(iOS 26.0, *) {
                  $0
                    .glassEffect(.regular.interactive())
                } else {
                  $0
                    .font(.title)
                    .fontWeight(.bold)
                    .background(
                      Circle()
                        .fill(.background.secondary)
                        .opacity(0.9)
                    )
                }
              }
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

    .onChange(of: routeManager.pendingRoute, initial: true, handlePendingRoute)

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
              Button {
                showShareLinkSheet = true
              } label: {
                Label(localized: .localizable(.shareLink), systemImage: "link")
              }

              if let url = viewModel.documentUrl {
                ShareLink(item: url) {
                  Label(localized: .localizable(.documentLink), systemImage: "safari")
                }
              }

              Menu {

                let deepLinks = viewModel.deepLinks

                if let url = deepLinks.withoutServer?.url {
                  ShareLink(item: url) {
                    Text(.localizable(.documentDeepLinkWithoutBackend))
                  }
                }

                if let url = deepLinks.withServer?.url {
                  ShareLink(item: url) {
                    Text(.localizable(.documentDeepLinkWithBackend))
                  }
                }

              } label: {
                Label(localized: .localizable(.documentDeepLink), systemImage: "app")
              }

              if case .loaded(url: let url, document: _) = viewModel.download {
                ShareLink(item: url) {
                  Label(localized: .localizable(.shareSheet), systemImage: "square.and.arrow.down")
                }
              }
            } label: {
              EmptyView()
            }
          }
      }
    }

    .sheet(isPresented: $showShareLinkSheet) {
      ShareLinkView(document: viewModel.document)
    }

    .sheet(isPresented: $showEditSheet) {
      editDetent = defaultEditDetent
      if !viewModel.userCanView {
        navPath?.wrappedValue.removeLast()
        // This should notify the document list that it needs to refresh
        viewModel.store.eventPublisher.send(.changeReceived(document: viewModel.document))
      }

    } content: {
      DocumentEditView(
        store: viewModel.store,
        document: $viewModel.document,
        navPath: navPath
      )
      .environmentObject(viewModel.store)
      .environmentObject(errorController)
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
    static func == (lhs: WebView, rhs: WebView) -> Bool
  {
    lhs.url == rhs.url
  }

  var body: some View {
    WebViewInternal(
      url: url,
      topPadding: $topPadding,
      bottomPadding: $bottomPadding,
      safeAreaInsets: $safeAreaInsets,
      tapTask: $tapTask,
      load: load
    )
    .simultaneousGesture(
      ExclusiveGesture(
        LongPressGesture()
          .onEnded { finished in
            print("we long pressed \(finished)")
          },

        TapGesture()
          .onEnded {
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

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async
      -> WKNavigationActionPolicy
    {
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
    let scrollInsets = UIEdgeInsets(
      top: topPadding, left: 0,
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
  @StateObject var connectionManager = ConnectionManager(previewMode: true)

  @State var document: Document?
  @State var navPath = [NavigationState]()

  let documentId: UInt

  init(id documentId: UInt) {
    self.documentId = documentId
  }

  var body: some View {
    NavigationStack {
      VStack {
        if let document {
          DocumentDetailViewV3(
            store: store, connection: connectionManager.connection, document: document,
            navPath: $navPath)
        } else {
          Text("No document")
        }
      }
      .task {
        do {
          let documents = try await store.repository.documents(filter: .default).fetch(
            limit: 100_000)
          document = documents.first(where: { $0.id == documentId })
        } catch {
          print(error)
        }
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button("Done") {}
        }
      }
    }
    .environmentObject(store)
    .environmentObject(errorController)
    .environment(RouteManager.shared)
    .task {
      try? await store.fetchAll()
    }
  }
}

#Preview("DocumentDetailsView") {
  PreviewHelper(id: 2)
}

#Preview("Long title") {
  PreviewHelper(id: 2)
}
