//
//  ImagePipelineProvider.swift
//  swift-paperless
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Networking
import Nuke
import Observation

// @TODO: Simplify — the only thing that changes between connections is the URLSessionDelegate.
// Consider storing the delegate directly and making `pipeline` computed, or moving pipeline ownership
// into DocumentStore/repository (which already knows the delegate) so views don't carry a separate provider.

@MainActor
@Observable
final class ImagePipelineProvider {
  private(set) var pipeline: ImagePipeline

  init() {
    self.pipeline = ImagePipeline()
  }

  func update(delegate: (any URLSessionDelegate)?) {
    let dataLoader = DataLoader()
    if let delegate {
      dataLoader.delegate = delegate
    }
    pipeline = ImagePipeline(configuration: .init(dataLoader: dataLoader))
  }
}
