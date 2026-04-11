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

  var body: some View {
    IntegratedDocumentPreview(
      document: document, downloadState: downloadState, currentPage: $currentPage
    )
    .frame(minWidth: 200, minHeight: 200)
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

        guard let pdfDocument = PDFDocument(url: url) else {
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
    .aspectRatio(aspectRatio, contentMode: .fill)
  }
}

private struct PDFPagingPreview: View {
  let document: PDFDocument
  @Binding var currentPage: Int

  @State private var scrolledPage: Int? = 0

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
      LazyHStack(spacing: 0) {
        ForEach(0..<pageCount, id: \.self) { index in
          PDFPageView(
            document: document,
            pageIndex: index,
            aspectRatio: aspectRatio(for: index)
          )
          .containerRelativeFrame(.horizontal)
        }
      }
      .scrollTargetLayout()
    }
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $scrolledPage)
    .aspectRatio(firstPageAspectRatio, contentMode: .fit)
    .onChange(of: scrolledPage) { _, newValue in
      if let newValue {
        currentPage = newValue
      }
    }
    .onChange(of: currentPage) { _, newValue in
      if scrolledPage != newValue {
        scrolledPage = newValue
      }
    }
    .overlay(alignment: .bottom) {
      Text(.localizable(.pageIndicator((scrolledPage ?? 0) + 1, pageCount)))
        .font(.caption2)
        .fontWeight(.semibold)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .backport.glassEffect(
          .regular, in: Capsule(), orFill: .ultraThinMaterial
        )
        .contentTransition(.numericText())
        .animation(.default, value: scrolledPage)
        .padding(8)
    }
    .background(.white)
  }
}

private struct IntegratedDocumentPreview: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(ImagePipelineProvider.self) private var imagePipelineProvider
  @State private var showLoadingOverlay = false
  var document: Document
  var downloadState: DocumentDownloadState
  @Binding var currentPage: Int

  @StateObject private var image = FetchImage()

  private static let loadingOverlayDelay: Duration = .seconds(0.5)

  var body: some View {
    ZStack {

      switch downloadState {
      case .initial, .loading:
        image.image?
          .resizable()
          .scaledToFit()
          .blur(radius: 5, opaque: true)

      case .error:
        Label("Unable to load preview", systemImage: "eye.slash")
          .labelStyle(.iconOnly)
          .imageScale(.large)
          .frame(maxWidth: .infinity, alignment: .center)

      case .loaded(url: _, document: let pdfDocument):
        PDFPagingPreview(document: pdfDocument, currentPage: $currentPage)
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
    .animation(.easeOut(duration: 0.8), value: downloadState)

    .task {
      image.transaction = Transaction(animation: .linear(duration: 0.1))
      image.pipeline = imagePipelineProvider.pipeline
      do {
        try image.load(
          ImageRequest(urlRequest: store.repository.thumbnailRequest(document: document))
        )
      } catch {
        Logger.shared.error("Error loading document thumbnail: \(error)")
      }
    }
    .onChange(of: downloadState) { _, newState in
      if case .loading = newState {
        Task {
          try? await Task.sleep(for: Self.loadingOverlayDelay)
          guard !Task.isCancelled else { return }
          if case .loading = downloadState {
            showLoadingOverlay = true
          }
        }
      } else {
        showLoadingOverlay = false
      }
    }
  }
}

struct PopupDocumentPreview: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(ImagePipelineProvider.self) private var imagePipelineProvider
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
        pipeline: imagePipelineProvider.pipeline,
        image: image)
    }
  }
}
