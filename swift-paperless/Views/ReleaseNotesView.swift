//
//  ReleaseNotesView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.05.2024.
//

import Foundation
import MarkdownUI
import os
import SwiftUI

private struct ReleaseNotesError: LocalizedError {
    @MainActor
    init() {
        errorDescription = String(localized: .localizable(.releaseNotesLoadError(AppSettings.shared.currentAppVersion?.description ?? "(?)")))
    }

    var errorDescription: String?
}

@MainActor
class ReleaseNotesViewModel: ObservableObject {
    @Published var showReleaseNotes = false
    @Published var error: (any Error)? = nil
    @Published var content: String? = nil

    init() {
        Task { @MainActor in
            switch (AppSettings.shared.lastAppVersion, AppSettings.shared.currentAppVersion) {
            case (.none, .none), (.some(_), .none):
                // Current is somehow nil, not sure what to do
                break
            case (.none, .some(_)):
                // Last is nil but have current, probably initial install
                showReleaseNotes = true
            case let (.some(last), .some(current)):
                if current.release != last.release {
                    showReleaseNotes = true
                }
            }
        }
    }

    static let baseUrl = URL(string: "https://swift-paperless.gessinger.dev/release_notes/")!

    func loadReleaseNotes() async {
        guard let version = AppSettings.shared.currentAppVersion?.releaseString else {
            Logger.shared.error("Did not get current app version")
            return
        }

        let url = Self.baseUrl.appending(path: "md").appending(path: "v\(version).md")
        let request = URLRequest(url: url)
        Logger.shared.debug("Loading release notes from \(request.url!, privacy: .public)")

        do {
            let (data, response) = try await URLSession.shared.getData(for: request)
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                error = ReleaseNotesError()
            } else {
                content = String(decoding: data, as: UTF8.self)
            }
        } catch {
            Logger.shared.error("Error loading release notes: \(error)")
            self.error = error
        }
    }
}

struct ReleaseNotesView: View {
    @ObservedObject var releaseNotesModel: ReleaseNotesViewModel

    var body: some View {
        ScrollView(.vertical) {
            if let content = releaseNotesModel.content {
                Markdown(content, baseURL: ReleaseNotesViewModel.baseUrl)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = releaseNotesModel.error {
                VStack {
                    Text("😵")
                        .font(.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    if let errorDescription = (error as? any LocalizedError)?.errorDescription {
                        Text("\(errorDescription)")
                    } else {
                        Text("\(error.localizedDescription)")
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
            }
        }

        .safeAreaInset(edge: .bottom) {
            Button {
                releaseNotesModel.showReleaseNotes = false
            } label: {
                Text(.localizable(.ok))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
            }
            .padding()
            .buttonStyle(.borderedProminent)
            .background {
                Rectangle()
                    .fill(.thickMaterial)
                    .ignoresSafeArea(.container, edges: .bottom)
            }
        }

        .task {
            await releaseNotesModel.loadReleaseNotes()
        }
    }
}

private struct HelperView: View {
    @StateObject var model = ReleaseNotesViewModel()
    var body: some View {
        ReleaseNotesView(releaseNotesModel: model)
    }
}

#Preview {
    HelperView()
}
