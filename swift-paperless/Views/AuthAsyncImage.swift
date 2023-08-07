//
//  AuthAsyncImage.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.02.23.
//

import SwiftUI

#if os(macOS)
import Cocoa
typealias UIImage = NSImage
#endif

struct AuthAsyncImage<Content: View, Placeholder: View>: View {
    @State var image: Image?

    let getImage: () async -> Image?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        image: @escaping () async -> Image?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.getImage = image
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        if let image = image {
            content(image)
        }
        else {
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
