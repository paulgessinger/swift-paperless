//
//  AttachmentManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import Foundation
import SwiftUI

enum AttachmentError {
    case invalidAttachment
    case invalidImage
    case noAttachments
}

@MainActor
class AttachmentManager: ObservableObject {
    @Published var isLoading = true
    @Published var error: AttachmentError? = nil
    @Published private(set) var previewImage: Image?
    @Published var documentUrl: URL?

    @Published var importUrls: [URL] = []
}
