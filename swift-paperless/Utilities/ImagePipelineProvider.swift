//
//  ImagePipelineProvider.swift
//  swift-paperless
//
//  Created by Codex on 22.02.26.
//

import Foundation
import Networking
import Nuke
import SwiftUI

@MainActor
final class ImagePipelineProvider: ObservableObject {
    @Published private(set) var pipeline: ImagePipeline

    private var delegateIdentifier: ObjectIdentifier?

    init() {
        self.pipeline = Self.makePipeline(delegate: nil)
    }

    func update(delegate: (any URLSessionDelegate)?) {
        let id = delegate.map { ObjectIdentifier($0 as AnyObject) }
        guard id != delegateIdentifier else { return }

        delegateIdentifier = id
        pipeline = Self.makePipeline(delegate: delegate)
    }

    private static func makePipeline(delegate: (any URLSessionDelegate)?) -> ImagePipeline {
        let dataLoader = DataLoader()
        if let delegate {
            dataLoader.delegate = delegate
        }
        return ImagePipeline(configuration: .init(dataLoader: dataLoader))
    }
}
