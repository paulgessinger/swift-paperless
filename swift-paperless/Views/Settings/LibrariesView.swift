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
            text = try String(contentsOfFile: filepath)
        }
        catch {
            fatalError("Unable to load static text file")
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            Markdown(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle("Libraries")
                .padding()
        }
    }
}

struct LibrariesView_Previews: PreviewProvider {
    static var previews: some View {
        LibrariesView()
    }
}
