//
//  ImagePipelineProvider.swift
//  swift-paperless
//
//  Created by Codex on 22.02.26.
//

import Networking
import Nuke
import Observation
import Foundation

@MainActor
@Observable
final class ImagePipelineProvider {
    private(set) var pipeline: ImagePipeline

    private var delegateIdentifier: ObjectIdentifier?

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

