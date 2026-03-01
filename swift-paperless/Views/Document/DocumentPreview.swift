//
//  DocumentPreview.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 11.09.25.
//

import DataModel
import Nuke
import NukeUI
import SwiftUI
import os

private enum DownloadState: Equatable {
  case initial
  case loading
  case loaded(PDFThumbnail)
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

  var body: some View {
    IntegratedDocumentPreview(document: document)
      .frame(minWidth: 200, minHeight: 200)
  }
}

@MainActor
@Observable
private final class IntegratedDocumentPreviewModel {
  var download: DownloadState = .initial
  var downloadProgress: Double = 0.0

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
      do {
        guard
          let url = try await store.repository.download(
            documentID: document.id,
            progress: { @Sendable value in
              Task { @MainActor in
                self.downloadProgress = value
              }
            })
        else {
          download = .error
          return
        }

        guard let view = PDFThumbnail(file: url) else {
          download = .error
          return
        }
        download = .loaded(view)
      } catch {
        download = .error
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
      }

    default:
      break
    }
  }
}

private struct IntegratedDocumentPreview: View {
  @EnvironmentObject private var store: DocumentStore
  @Environment(ImagePipelineProvider.self) private var imagePipelineProvider
  @State private var viewModel = IntegratedDocumentPreviewModel()
  @State private var showLoadingOverlay = false
  var document: Document

  @StateObject private var image = FetchImage()

  private static let loadingOverlayDelay: Duration = .seconds(0.5)

  var body: some View {
    ZStack {

      switch viewModel.download {
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

      case .loaded(let view):
        view
          .background(.white)
      }
    }

    .overlay {
      if showLoadingOverlay {
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
        .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.3), value: showLoadingOverlay)
    .animation(.easeOut(duration: 0.8), value: viewModel.download)

    .task {
      await viewModel.loadDocument(
        store: store,
        document: document,
        pipeline: imagePipelineProvider.pipeline,
        image: image)
    }
    .onChange(of: viewModel.download) { _, newState in
      if case .loading = newState {
        Task {
          try? await Task.sleep(for: Self.loadingOverlayDelay)
          guard !Task.isCancelled else { return }
          if case .loading = viewModel.download {
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

      case .loaded(let view):
        view.image?
          .resizable()
          .scaledToFit()
          .background(.white)
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
