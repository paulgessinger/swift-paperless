//
//  ReleaseNotesView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.05.2024.
//

import Common
import Foundation
import MarkdownUI
import os
import SwiftUI

private struct ReleaseNotesError: LocalizedError {
    @MainActor
    init(version: AppVersion?) {
        errorDescription = String(localized: .localizable(.releaseNotesLoadError(version?.description ?? "(?)")))
    }

    var errorDescription: String?
}

@MainActor
class ReleaseNotesViewModel: ObservableObject {
    @Published var showReleaseNotes = false

    enum Status {
        case none
        case content(MarkdownContent)
        case error(any Error)
    }

    @Published private(set) var status: Status = .none

    private let appVersion: AppVersion?
    private let appConfiguration: AppConfiguration?

    init(version: AppVersion? = nil, appConfiguration: AppConfiguration? = nil) {
        appVersion = version ?? AppSettings.shared.currentAppVersion
        self.appConfiguration = appConfiguration ?? Bundle.main.appConfiguration

        Task { @MainActor in
            switch (AppSettings.shared.lastAppVersion, appVersion) {
            case (.none, .none), (.some(_), .none):
                // Current is somehow nil, not sure what to do
                break
            case (.none, .some(_)):
                // Last is nil but have current, probably initial install
                showReleaseNotes = true
            case let (.some(last), .some(current)):
                if current != last {
                    showReleaseNotes = true
                }
            }
        }
    }

    static let baseUrl = #URL("https://swift-paperless.gessinger.dev/release_notes/")
    static let githubUrl = #URL("https://api.github.com")

    private func loadAppStoreReleaseNotes(for version: AppVersion) async throws {
        let url = Self.baseUrl.appending(path: "md").appending(path: "v\(version.version).md")
        let request = URLRequest(url: url)
        Logger.shared.debug("Loading release notes for AppStore config from \(request.url!, privacy: .public)")

        do {
            let (data, response) = try await URLSession.shared.getData(for: request)
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                throw ReleaseNotesError(version: appVersion)
            } else {
                status = .content(MarkdownContent(String(decoding: data, as: UTF8.self)))
            }
        }
    }

    private func loadTestFlightReleaseNotes(for version: AppVersion) async throws {
        guard let url = URL(string: "https://api.github.com/repos/paulgessinger/swift-paperless/releases/tags/builds/\(version.version)/\(version.build)") else {
            throw ReleaseNotesError(version: appVersion)
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData

        Logger.shared.debug("Loading release notes for TestFlight config from \(request.url!, privacy: .public)")
        do {
            let (data, response) = try await URLSession.shared.getData(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
                throw ReleaseNotesError(version: appVersion)
            }

            struct Release: Decodable {
                let name: String
                let body: String
                let tag_name: String
            }

            let release = try JSONDecoder().decode(Release.self, from: data)

            status = .content(MarkdownContent {
                Heading {
                    release.name
                }

                Paragraph {
                    Code(release.tag_name)
                }

                MarkdownContent {
                    release.body
                }
            })
        }
    }

    func loadReleaseNotes() async {
        guard let version = appVersion else {
            return
        }

        do {
            switch appConfiguration {
            case .AppStore:
                // App Store release notes
                try await loadAppStoreReleaseNotes(for: version)
            default:
                // TestFlight release notes
                try await loadTestFlightReleaseNotes(for: version)
            }
        } catch is CancellationError {
            // noop
        } catch {
            Logger.shared.error("Error loading release notes: \(error)")
            status = .error(error)
        }
    }
}

private struct ReleaseNotesBareView: View {
    var status: ReleaseNotesViewModel.Status

    var body: some View {
        ScrollView(.vertical) {
            switch status {
            case .none:
                EmptyView()
            case let .content(content):
                Markdown(content, baseURL: ReleaseNotesViewModel.baseUrl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            case let .error(error):
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
    }
}

struct ReleaseNotesCoverView: View {
    @ObservedObject var releaseNotesModel: ReleaseNotesViewModel

    var body: some View {
        ReleaseNotesBareView(status: releaseNotesModel.status)

            .safeAreaInset(edge: .bottom) {
                Button {
                    releaseNotesModel.showReleaseNotes = false
                } label: {
                    Text(.localizable(.ok))
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                }
                .padding(.vertical, 10)

                .foregroundStyle(.white)
                .bold()
                .background {
                    Capsule()
                        .fill(.accent)
                }
                .padding()

                .background {
                    Capsule()
                        .fill(.thickMaterial)
                }
                .padding(.horizontal, 20)
            }

            .task {
                await releaseNotesModel.loadReleaseNotes()
            }
    }
}

struct ReleaseNotesView: View {
    @StateObject private var model = ReleaseNotesViewModel()

    var body: some View {
        ReleaseNotesBareView(status: model.status)
            .task {
                await model.loadReleaseNotes()
            }
    }
}

private struct HelperView: View {
    @StateObject var model = ReleaseNotesViewModel()
    var body: some View {
        ReleaseNotesCoverView(releaseNotesModel: model)
    }

    init(version: AppVersion? = nil, appConfiguration: AppConfiguration? = nil) {
        _model = StateObject(wrappedValue: ReleaseNotesViewModel(version: version, appConfiguration: appConfiguration))
    }
}

#Preview("Current") {
    HelperView()
}

#Preview("TestFlight") {
    HelperView(version: AppVersion(version: "1.8.0", build: "142"), appConfiguration: .TestFlight)
}

#Preview("AppStore") {
    HelperView(version: AppVersion(version: "1.7.1", build: "142"), appConfiguration: .AppStore)
}
