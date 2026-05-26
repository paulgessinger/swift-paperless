//
//  AttachmentManager.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import Foundation
import SwiftUI

public enum AttachmentError {
  case invalidAttachment
  case noAttachments
}

@MainActor
public class AttachmentManager: ObservableObject {
  @Published public var isLoading = true
  @Published public var error: AttachmentError? = nil
  @Published public private(set) var previewImage: Image?
  @Published public var documentUrl: URL?

  @Published public var importUrls: [URL] = []
  @Published public var totalInputs: Int = 0

  public init() {}
}
