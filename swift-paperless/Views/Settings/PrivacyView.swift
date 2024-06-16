//
//  PrivacyView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.09.23.
//

import MarkdownUI
import SwiftUI

struct PrivacyView: View {
    private static let url = URL(string: "https://raw.githubusercontent.com/paulgessinger/swift-paperless/main/docs/privacy.md")!

    @State private var text: String? = nil
    @State private var title: String = .init(localized: .settings.detailsPrivacy)

    var body: some View {
        ScrollView(.vertical) {
            Markdown(text ?? "")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .overlay {
            if text == nil {
                ProgressView(String(localized: .localizable(.loading)))
            }
        }
        .navigationTitle(title)
        .task {
            do {
                let request = URLRequest(url: PrivacyView.url)
                let (data, _) = try await URLSession.shared.getData(for: request)
                withAnimation {
                    text = String(decoding: data, as: UTF8.self)
                    title = ""
                }
            } catch {
                withAnimation {
                    text = String(localized: .settings.detailsPrivacyLoadError(PrivacyView.url.absoluteString))
                }
            }
        }
    }
}

#Preview {
    PrivacyView()
}
