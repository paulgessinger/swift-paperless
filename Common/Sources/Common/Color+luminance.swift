//
//  Color+luminance.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.09.2024.
//

import SwiftUI

extension Color {
  public var luminance: Double {
    // https://github.com/paperless-ngx/paperless-ngx/blob/0dcfb97824b6184094290138fe401d8368722483/src/documents/serialisers.py#L317-L328

    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0

    #if canImport(UIKit)
      UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #elseif canImport(AppKit)
      NSColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    #endif

    return sqrt(0.299 * pow(red, 2) + 0.587 * pow(green, 2) + 0.114 * pow(blue, 2))
  }
}
