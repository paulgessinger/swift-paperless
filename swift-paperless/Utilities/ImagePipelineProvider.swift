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
