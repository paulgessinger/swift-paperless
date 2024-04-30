//
//  NSData+mimeType.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 30.04.2024.
//

import Foundation
import UniformTypeIdentifiers

extension NSData {
    var mimeType: String {
        let c: UInt8 = self[0]
        return switch c {
        case 0xFF:
            "image/jpeg"
        case 0x89:
            "image/png"
        case 0x47:
            "image/gif"
        case 0x4D, 0x49:
            "image/tiff"
        case 0x25:
            "application/pdf"
        case 0xD0:
            "application/vnd"
        case 0x46:
            "text/plain"
        default:
            "application/octet-stream"
        }
    }
}
