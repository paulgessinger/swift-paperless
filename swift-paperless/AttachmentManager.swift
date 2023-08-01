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
}

class AttachmentManager: ObservableObject {
    @Published var isLoading = true
    @Published var error: AttachmentError? = nil
    @Published private(set) var previewImage: Image?
    @Published var documentUrl: URL?

    func setDocumentUrl(_ url: URL) {
        Task { await MainActor.run { documentUrl = url }}
    }

    func setLoading(_ value: Bool) {
        Task { await MainActor.run { isLoading = value }}
    }

    func setPreviewImage(_ image: Image) {
        Task {
            await MainActor.run {
                previewImage = image
            }
        }
    }
}
