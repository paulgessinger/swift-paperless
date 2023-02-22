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

    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    init(
        url: URL?, @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    func getImage() async -> UIImage? {
        guard let url = url else { return nil }

//        print("Load image at \(url)")

        var request = URLRequest(url: url)
        request.setValue("Token \(API_TOKEN)", forHTTPHeaderField: "Authorization")

        do {
            let (data, res) = try await URLSession.shared.data(for: request)

            guard (res as? HTTPURLResponse)?.statusCode == 200 else {
                fatalError("Did not get good response for image")
            }

//            try await Task.sleep(for: .seconds(2))

            return UIImage(data: data)
        }
        catch { return nil }
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
                let image = await getImage()
                withAnimation {
                    self.uiImage = image
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
