//
//  AuthAsyncImage.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import SwiftUI

#if os(macOS)
  import Cocoa

  public typealias UIImage = NSImage
#endif

public struct AuthAsyncImage<Content: View, Placeholder: View>: View {
  @State public var image: Image?

  public let getImage: () async -> Image?
  public let content: (Image) -> Content
  public let placeholder: () -> Placeholder

  public init(
    image: @escaping () async -> Image?,
    @ViewBuilder content: @escaping (Image) -> Content,
    @ViewBuilder placeholder: @escaping () -> Placeholder
  ) {
    getImage = image
    self.content = content
    self.placeholder = placeholder
  }

  public var body: some View {
    if let image {
      content(image)
    } else {
      placeholder().task {
        let image = await getImage()
        withAnimation {
          self.image = image
        }
      }
    }
  }
}

// struct AuthAsyncImage_Previews: PreviewProvider {
//    static var previews: some View {
//        AuthAsyncImage()
//    }
// }
