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
    @State var uiImage: UIImage?

    let getImage: () async -> (Bool, UIImage?)
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        image: @escaping () async -> (Bool, UIImage?), @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.getImage = image
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        if let uiImage = uiImage {
#if os(macOS)
            content(Image(nsImage: uiImage))
#else
            content(Image(uiImage: uiImage))
#endif
        }
        else {
            placeholder().task {
                let (cached, image) = await getImage()
                if cached { self.uiImage = image }
                else {
                    withAnimation {
                        self.uiImage = image
                    }
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
