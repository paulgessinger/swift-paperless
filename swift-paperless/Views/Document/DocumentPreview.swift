//
//  DocumentPreview.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.09.25.
//

import DataModel
import Nuke
import NukeUI
import PDFKit
import SwiftUI
import os

/// Per-page zoom transition ID. Every visible page registers its own source
/// (so the matched-transition modifier can be unconditional, avoiding view-
/// identity churn during scroll), and the full-preview destination resolves
/// the right source by combining the same base with whichever page the user
/// tapped.
struct PDFPageZoomID: Hashable {
  let base: AnyHashable
  let index: Int
}

private enum DownloadState: Equatable {
  case initial
  case loading
  case loaded(PDFDocument)
  case error

  static func == (lhs: DownloadState, rhs: DownloadState) -> Bool {
    switch (lhs, rhs) {
    case (.initial, .initial), (.loading, .loading), (.loaded, .loaded), (.error, .error):
      true
    default:
      false
    }
  }
}

struct DocumentPreview: View {
  var document: Document
  var downloadState: DocumentDownloadState
  @Binding var currentPage: Int

  var transitionID: AnyHashable? = nil
  var transitionNamespace: Namespace.ID? = nil
  var onTap: ((Int) -> Void)? = nil

  var body: some View {
    IntegratedDocumentPreview(
      document: document,
      downloadState: downloadState,
      currentPage: $currentPage,
      transitionID: transitionID,
      transitionNamespace: transitionNamespace,
      onTap: onTap
    )
  }
}

@MainActor
@Observable
private final class IntegratedDocumentPreviewModel {
  var download: DownloadState = .initial
  var downloadProgress: Double = 0.0
  var hasReceivedProgress = false

  func loadDocument(
    store: DocumentStore,
    document: Document,
    pipeline: ImagePipeline,
    image: FetchImage
  ) async {

    // @TODO: If we have a cache hit on the downloaded PDF, skip the blurred thumbnail

    image.transaction = Transaction(animation: .linear(duration: 0.1))

    image.pipeline = pipeline

    do {
      try image.load(
        ImageRequest(urlRequest: store.repository.thumbnailRequest(document: document))
      )
    } catch {
      Logger.shared.error("Error loading document thumbnail: \(error)")
    }

    switch download {
    case .initial:
      download = .loading
      hasReceivedProgress = false
      downloadProgress = 0
      do {
        guard
          let url = try await store.repository.download(
            documentID: document.id,
            original: false,
            progress: { @Sendable value in
              Task { @MainActor in
                self.hasReceivedProgress = true
                self.downloadProgress = value
              }
            })
        else {
          download = .error
          return
        }

        guard let pdfDocument = await PDFDocument.loadBackground(url: url) else {
          download = .error
          return
        }
        download = .loaded(pdfDocument)
      } catch {
        download = .error
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
      }

    default:
      break
    }
  }
}

private struct PDFPageView: View {
  let document: PDFDocument
  let pageIndex: Int
  let aspectRatio: CGFloat

  var body: some View {
    PDFKitView(
      document: document,
      displayMode: .singlePage,
      pageShadows: false,
      autoScales: true,
      userInteraction: false,
      displayPageBreaks: false,
      pageBreakMargins: .zero,
      pageIndex: pageIndex
    )
    .aspectRatio(aspectRatio, contentMode: .fit)
    .background(.white)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 20, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1 / UIScreen.main.scale)
    )
  }
}

private struct PDFPagingPreview: View {
  let document: PDFDocument
  @Binding var currentPage: Int

  var maxHeight: CGFloat? = nil
  var transitionID: AnyHashable? = nil
  var transitionNamespace: Namespace.ID? = nil
  // Receives the tapped page's index. Callers use this to set the destination
  // sourceID *and* the initial preview page in the same handler — relying on
  // the binding chain to propagate `currentPage` to the parent before the
  // cover renders is unreliable.
  var onTap: ((Int) -> Void)? = nil

  @State private var scrolledPage: Int? = 0
  // Set to true when the *tap handler* mutates `currentPage`. The
  // `onChange(currentPage)` syncs scroll on external updates (e.g. when the
  // full preview navigates pages), but a tap shouldn't jump the small preview
  // before the cover even opens — we'd just see a half-second of scroll
  // animation tearing under the zoom transition. The flag is consumed by the
  // very next `onChange` and reset, so subsequent external updates still sync.
  @State private var skipNextScrollSync = false

  static let pageInset: CGFloat = 80
  static let regularPageInset: CGFloat = 32
  private static let pageSpacing: CGFloat = 16

  private var pageCount: Int {
    document.pageCount
  }

  private func aspectRatio(for pageIndex: Int) -> CGFloat {
    guard let page = document.page(at: pageIndex) else { return 1.0 }
    let size = page.bounds(for: .trimBox).size
    return size.width / size.height
  }

  private var firstPageAspectRatio: CGFloat {
    aspectRatio(for: 0)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(spacing: Self.pageSpacing) {
        ForEach(0..<pageCount, id: \.self) { index in
          let isActive = index == (scrolledPage ?? 0)
          // iPhone: pages are full-width and the peek slivers belong to
          // neighbours we can't really aim at — keep the original
          // active-only tap. iPad: pages are smaller and clearly distinct,
          // so allow tapping any of them.
          let canTap = onTap != nil && (maxHeight != nil || isActive)
          Button {
            // Update currentPage *before* firing onTap so the destination's
            // navigationTransitionZoom resolves to this page's source ID.
            // Set the flag first so the resulting onChange doesn't drag the
            // scroll view to the new page — otherwise the small preview snaps
            // sideways during the cover transition.
            if currentPage != index {
              skipNextScrollSync = true
              currentPage = index
            }
            onTap?(index)
          } label: {
            PDFPageView(
              document: document,
              pageIndex: index,
              aspectRatio: aspectRatio(for: index)
            )
            .apply {
              if let maxHeight {
                // Regular size class: pin height; width follows the page's
                // aspect ratio so multiple pages naturally peek on either
                // side. We need a *definite* height (not maxHeight) so the
                // aspect-ratio chain has something to derive width from —
                // otherwise the layout collapses to zero in the horizontal
                // ScrollView.
                $0.frame(height: maxHeight)
              } else {
                $0
                  .containerRelativeFrame(.horizontal)
                  .aspectRatio(aspectRatio(for: index), contentMode: .fit)
              }
            }
          }
          .buttonStyle(.plain)
          .allowsHitTesting(canTap)
          .apply {
            // Apply the source unconditionally per-page so view identity stays
            // stable when scrolling. The destination picks the matching ID via
            // PDFPageZoomID(index: previewPage); other sources are ignored.
            if let transitionID, let transitionNamespace {
              $0.backport.matchedTransitionSource(
                id: PDFPageZoomID(base: transitionID, index: index),
                in: transitionNamespace
              )
            } else {
              $0
            }
          }
        }
      }
      .scrollTargetLayout()
      .fixedSize(horizontal: false, vertical: true)
    }
    .contentMargins(
      .horizontal,
      maxHeight != nil ? Self.regularPageInset : Self.pageInset,
      for: .scrollContent
    )
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $scrolledPage, anchor: .center)
    .scrollClipDisabled()
    .onChange(of: scrolledPage) { _, newValue in
      if let newValue {
        currentPage = newValue
      }
    }
    .onChange(of: currentPage) { _, newValue in
      if skipNextScrollSync {
        skipNextScrollSync = false
        return
      }
      if scrolledPage != newValue {
        scrolledPage = newValue
      }
    }
  }
}

private struct IntegratedDocumentPreview: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var showLoadingOverlay = false
  @State private var thumbnailHidden = false
  var document: Document
  var downloadState: DocumentDownloadState
  @Binding var currentPage: Int

  var transitionID: AnyHashable? = nil
  var transitionNamespace: Namespace.ID? = nil
  var onTap: ((Int) -> Void)? = nil

  @StateObject private var image = FetchImage()

  private static let loadingOverlayDelay: Duration = .seconds(0.5)
  private static let pdfFadeInDuration: TimeInterval = 0.35
  // Regular-size-class height cap. iPad screens are tall enough that an
  // unconstrained, container-wide page would push the rest of the detail view
  // off-screen, so we bound the preview and let pages size by their aspect.
  private static let regularMaxHeight: CGFloat = 420

  private var isRegularWidth: Bool {
    horizontalSizeClass == .regular
  }

  private var pdfMaxHeight: CGFloat? {
    isRegularWidth ? Self.regularMaxHeight : nil
  }

  private var horizontalPadding: CGFloat {
    isRegularWidth ? PDFPagingPreview.regularPageInset : PDFPagingPreview.pageInset
  }

  var body: some View {
    ZStack {
      if case .error = downloadState {
        Label("Unable to load preview", systemImage: "eye.slash")
          .labelStyle(.iconOnly)
          .imageScale(.large)
          .frame(maxWidth: .infinity, alignment: .center)
      } else {
        // Thumbnail acts as a stable underlay while the PDF fades in on top.
        // Avoids both layers being ~50% transparent mid-animation, which would
        // bleed the dark background through and look like "fading through black".
        // Once the PDF is fully opaque, `thumbnailHidden` flips and the
        // thumbnail unmounts — without animation, since the flip happens
        // outside the .animation(value: downloadState) scope — so the now-
        // invisible thumbnail no longer peeks through during page scrolling.
        if !thumbnailHidden {
          let thumbnail = image.image?
            .resizable()
            .scaledToFit()
            .blur(radius: 5, opaque: true)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
              RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1 / UIScreen.main.scale)
            )

          if let pdfMaxHeight {
            // The horizontal ScrollView leading-aligns the first page (its
            // content offset clamps to zero, so `scrollPosition(.center)` can't
            // actually centre page 0). Match that placement here so the
            // thumbnail and the first PDF page occupy the same rect — without
            // this, the thumbnail centres and the cross-fade visibly jumps
            // sideways once the PDF loads.
            thumbnail
              .frame(height: pdfMaxHeight)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.leading, horizontalPadding)
              .transition(.identity)
          } else {
            thumbnail
              .padding(.horizontal, horizontalPadding)
              .transition(.identity)
          }
        }

        if case .loaded(url: _, document: let pdfDocument) = downloadState {
          PDFPagingPreview(
            document: pdfDocument,
            currentPage: $currentPage,
            maxHeight: pdfMaxHeight,
            transitionID: transitionID,
            transitionNamespace: transitionNamespace,
            onTap: onTap
          )
          .transition(.opacity)
          .scrollDisabled(!thumbnailHidden)
        }
      }
    }
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(Color(.systemGray6))
    .overlay(alignment: .bottom) {
      // Always mount the indicator while loaded so the glass effect can
      // settle against the final PDF background before the user sees it.
      // We then drive visibility with an opacity modifier rather than a
      // view-tree transition — the latter forces the glass material to
      // re-sample its backdrop on insertion, which reads as a brief dark
      // flash before it stabilises.
      if case .loaded(url: _, document: let pdfDocument) = downloadState,
        !isRegularWidth
      {
        // Hidden on iPad: scroll no longer drives `currentPage`, so the
        // indicator would only update on tap — confusing rather than helpful.
        Text(.localizable(.pageIndicator(currentPage + 1, pdfDocument.pageCount)))
          .font(.caption2)
          .fontWeight(.semibold)
          .padding(.horizontal, 8)
          .padding(.vertical, 4)
          .backport.glassEffect(
            .regular, in: Capsule(), orFill: .ultraThinMaterial
          )
          .contentTransition(.numericText())
          .animation(.default, value: currentPage)
          .padding(.bottom, 24)
          .allowsHitTesting(false)
          .opacity(thumbnailHidden ? 1 : 0)
          .animation(.easeOut(duration: 0.2).delay(0.4), value: thumbnailHidden)
      }
    }

    .overlay {
      if showLoadingOverlay {
        VStack {
          Text(.localizable(.loading))
            .foregroundStyle(.primary)
          LinearProgressBar(mode: .indeterminate)
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
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: showLoadingOverlay)
    .animation(.easeOut(duration: Self.pdfFadeInDuration), value: downloadState)

    .task {
      image.transaction = Transaction(animation: .linear(duration: 0.1))
      image.pipeline = store.imagePipeline
      do {
        try image.load(
          ImageRequest(urlRequest: store.repository.thumbnailRequest(document: document))
        )
      } catch {
        Logger.shared.error("Error loading document thumbnail: \(error)")
      }
    }
    .task(id: downloadState) {
      // Synchronous resets first so a fast state flip clears stale flags
      // immediately, before the awaits below.
      if case .loading = downloadState {} else { showLoadingOverlay = false }
      if case .loaded = downloadState {} else { thumbnailHidden = false }

      // SwiftUI cancels this task (throwing CancellationError out of the
      // sleep) when downloadState changes again or the view disappears, so
      // a stale schedule from a prior state can't flip flags out from under
      // the current one.
      do {
        switch downloadState {
        case .loading:
          try await Task.sleep(for: Self.loadingOverlayDelay)
          showLoadingOverlay = true
        case .loaded:
          try await Task.sleep(for: .seconds(Self.pdfFadeInDuration))
          thumbnailHidden = true
        case .initial, .error:
          break
        }
      } catch is CancellationError {
        // Superseded by a newer state — drop this run.
      } catch {
        Logger.shared.error("Unexpected error scheduling preview state: \(error)")
      }
    }
  }
}

struct PopupDocumentPreview: View {
  @EnvironmentObject private var store: DocumentStore
  @State private var viewModel = IntegratedDocumentPreviewModel()
  var document: Document

  @StateObject private var image = FetchImage()

  var body: some View {
    ZStack {

      switch viewModel.download {
      case .initial, .loading:
        image.image?
          .resizable()
          .scaledToFit()
          .blur(radius: 10)

      case .error:
        Label("Unable to load preview", systemImage: "eye.slash")
          .labelStyle(.iconOnly)
          .imageScale(.large)
          .frame(maxWidth: .infinity, alignment: .center)

      case .loaded(let pdfDocument):
        if let page = pdfDocument.page(at: 0) {
          let size = page.bounds(for: .trimBox).size
          PDFKitView(
            document: pdfDocument,
            displayMode: .singlePage,
            pageShadows: false,
            autoScales: true,
            userInteraction: false,
            displayPageBreaks: false,
            pageBreakMargins: .zero,
            pageIndex: 0
          )
          .aspectRatio(size.width / size.height, contentMode: .fill)
          .background(.white)
        }
      }
    }

    .transition(.opacity)
    .animation(.easeOut(duration: 0.8), value: viewModel.download)

    .task {
      await viewModel.loadDocument(
        store: store,
        document: document,
        pipeline: store.imagePipeline,
        image: image)
    }
  }
}
