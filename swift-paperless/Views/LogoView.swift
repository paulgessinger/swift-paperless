//
//  LogoView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 25.03.23.
//

import SwiftUI

struct LogoView: View {
    var body: some View {
        HStack {
            Image(systemName: "leaf.fill")
                .foregroundColor(.accentColor)
            Text(.localizable.appName)
        }
    }
}

struct LogoView_Previews: PreviewProvider {
    static var previews: some View {
        LogoView()
    }
}
