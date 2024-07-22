//
//  QuickLookPreviewWrapper.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import Foundation
import SwiftUI

struct DocumentDetailPreviewWrapper: View {
//    @Binding var state: DocumentDownloadState
    @State var viewModel: DocumentDetailModel

    var body: some View {
        NavigationStack {
            if case let .loaded(thumb) = viewModel.download {
                QuickLookPreview(url: thumb.file)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarBackground(Color(white: 0.4, opacity: 0.0), for: .navigationBar)
                    .navigationTitle(String(localized: .localizable(.documentDetailPreviewTitle)))
                    .ignoresSafeArea(.container, edges: [.bottom])
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItemGroup(placement: .topBarTrailing) {
                            ShareLink(item: thumb.file) {
                                Label(localized: .localizable(.share), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
            }
        }
    }
}
