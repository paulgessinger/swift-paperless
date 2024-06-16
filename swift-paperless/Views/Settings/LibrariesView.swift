//
//  LibrariesView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.09.23.
//

import MarkdownUI
import SwiftUI

struct LibrariesView: View {
    var text: String

    init() {
        let filepath = Bundle.main.path(forResource: "libraries", ofType: "md")!
        do {
            let raw = try String(contentsOfFile: filepath)
            let begin = raw.range(of: "---")!.upperBound
            text = String(raw.suffix(from: begin))
        } catch {
            fatalError(String(localized: .settings(.detailsLibrariesLoadError)))
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            Markdown(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle(Text(.settings(.detailsLibraries)))
                .padding()
        }
    }
}

#Preview {
    LibrariesView()
}
