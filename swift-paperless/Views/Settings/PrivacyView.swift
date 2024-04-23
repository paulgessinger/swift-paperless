//
//  PrivacyView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.09.23.
//

import MarkdownUI
import SwiftUI

struct PrivacyView: View {
    private static let url = URL(string: "https://raw.githubusercontent.com/paulgessinger/swift-paperless/main/privacy.md")!

    @State var text: String? = nil

    var body: some View {
        ScrollView(.vertical) {
            if let text {
                Markdown(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            } else {
                ProgressView(String(localized: .localizable.loading))
            }
        }
        .navigationTitle(Text(.settings.detailsPrivacy))
        .task {
            do {
                let request = URLRequest(url: PrivacyView.url)
                let (data, _) = try await URLSession.shared.getData(for: request)
                text = String(decoding: data, as: UTF8.self)
            } catch {
                await MainActor.run {
                    text = String(localized: .settings.detailsPrivacyLoadError(PrivacyView.url.absoluteString))
                }
            }
        }
    }
}

struct PrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyView()
    }
}
