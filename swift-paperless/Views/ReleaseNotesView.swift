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

@MainActor
class ReleaseNotesViewModel: ObservableObject {
    @Published var showReleaseNotes = false
    @Published var error: Error? = nil
    @Published var content: String? = nil

    init() {
        Task { @MainActor in
            if AppSettings.shared.lastAppVersion != AppSettings.shared.currentAppVersion {
                showReleaseNotes = true
            }
        }
    }

    private static let baseUrl = URL(string: "https://raw.githubusercontent.com/paulgessinger/swift-paperless/main/docs/release_notes/")!

    func loadReleaseNotes() async {
        guard let version = AppSettings.shared.currentAppVersion?.releaseString else {
            Logger.shared.error("Did not get current app version")
            return
        }

        let url = Self.baseUrl.appending(path: "v\(version).md")
        let request = URLRequest(url: url)
        Logger.shared.debug("Loading release notes from \(request.url!, privacy: .public)")

        do {
            let (data, _) = try await URLSession.shared.getData(for: request)
            print("set")
            content = String(decoding: data, as: UTF8.self)
        } catch {
            Logger.shared.error("Error loading release noted: \(error)")
            self.error = error
        }
    }
}

struct ReleaseNotesView: View {
    @ObservedObject var releaseNotesModel: ReleaseNotesViewModel

    var body: some View {
        ScrollView(.vertical) {
            if let content = releaseNotesModel.content {
                Markdown(content)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let error = releaseNotesModel.error {
                VStack {
                    Text("😵")
                        .font(.title)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    Text("\(error.localizedDescription)")
                }
            }
        }

        .safeAreaInset(edge: .bottom) {
            Button {
                releaseNotesModel.showReleaseNotes = false
            } label: {
                Text(.localizable.ok)
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
