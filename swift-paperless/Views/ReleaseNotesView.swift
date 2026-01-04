//
//  ReleaseNotesView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 18.05.2024.
//

import Common
import Foundation
import MarkdownUI
import SwiftUI
import os

private struct ReleaseNotesError: LocalizedError {
  @MainActor
  init(version: AppVersion?) {
    errorDescription = String(
      localized: .localizable(.releaseNotesLoadError(version?.description ?? "(?)")))
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
      case (.some(let last), .some(let current)):
        if current != last {
          showReleaseNotes = true
        }
      }
    }
  }

  static let baseUrl = #URL("https://swift-paperless.gessinger.dev/release_notes/")
  static let githubUrl = #URL("https://api.github.com")
  static let githubRepo = "paulgessinger/swift-paperless"
  static let githubIssuesBaseUrl = "https://github.com/paulgessinger/swift-paperless/issues"

  private func convertIssueReferencesToLinks(_ text: String) -> String {
    var result = text

    // Convert standalone GitHub issue URLs to markdown links
    // Only if not already in a markdown link format [text](url)
    let urlRegex = /https:\/\/github\.com\/([\w\-]+)\/([\w\-]+)\/issues\/(\d+)/
    // Process matches in reverse to maintain correct string indices
    let urlMatches = Array(result.matches(of: urlRegex).reversed())
    for match in urlMatches {
      // Check if already in a markdown link by looking at preceding characters
      let matchStart = match.range.lowerBound
      let isPrecededByMarkdownLink =
        matchStart >= result.index(result.startIndex, offsetBy: 2)
        && result[result.index(matchStart, offsetBy: -2)..<matchStart] == "]("

      guard !isPrecededByMarkdownLink else { continue }

      // Only process URLs that match our repository
      let owner = match.1
      let repo = match.2
      let issueNumber = match.3
      if "\(owner)/\(repo)" == Self.githubRepo {
        let url = result[match.range]
        let markdownLink = "[#\(issueNumber)](\(url))"
        result.replaceSubrange(match.range, with: markdownLink)
      }
    }

    // Convert standalone #NUMBER references to markdown links
    // Only if not already in a markdown link format [text](#NUMBER) or [#NUMBER]
    let issueRegex = /#(\d+)\b/
    // Process matches in reverse to maintain correct string indices
    let issueMatches = Array(result.matches(of: issueRegex).reversed())
    for match in issueMatches {
      let matchStart = match.range.lowerBound

      // Check if preceded by ]( or [
      let isPrecededByMarkdownLink =
        matchStart >= result.index(result.startIndex, offsetBy: 2)
        && result[result.index(matchStart, offsetBy: -2)..<matchStart] == "]("
      let isPrecededByBracket =
        matchStart >= result.index(result.startIndex, offsetBy: 1)
        && result[result.index(matchStart, offsetBy: -1)..<matchStart] == "["

      guard !isPrecededByMarkdownLink && !isPrecededByBracket else { continue }

      let issueNumber = match.1
      let markdownLink = "[#\(issueNumber)](\(Self.githubIssuesBaseUrl)/\(issueNumber))"
      result.replaceSubrange(match.range, with: markdownLink)
    }

    return result
  }

  private func loadAppStoreReleaseNotes(for version: AppVersion) async throws {
    let url = Self.baseUrl.appending(path: "md").appending(path: "v\(version.version).md")
    let request = URLRequest(url: url)
    Logger.shared.debug(
      "Loading release notes for AppStore config from \(request.url!, privacy: .public)")

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
    guard
      let url = URL(
        string: "\(Self.githubUrl)/repos/\(Self.githubRepo)/releases?per_page=100"
      )
    else {
      throw ReleaseNotesError(version: appVersion)
    }

    var request = URLRequest(url: url)
    request.cachePolicy = .reloadIgnoringLocalCacheData

    Logger.shared.debug(
      "Loading release notes for TestFlight config from \(url, privacy: .public)")
    do {
      let (data, response) = try await URLSession.shared.getData(for: request)
      guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
        throw ReleaseNotesError(version: appVersion)
      }

      struct Release: Decodable {
        let name: String
        let body: String
        let tag_name: String
        let prerelease: Bool
        let published_at: String
      }

      let releases = try JSONDecoder().decode([Release].self, from: data)

      // Filter for pre-releases matching the current version
      let versionPrefix = "builds/\(version.version)/"
      let matchingReleases = releases.filter { release in
        release.prerelease && release.tag_name.hasPrefix(versionPrefix)
      }

      // Parse and sort by build number (descending)
      let sortedReleases =
        matchingReleases
        .compactMap { release -> (Release, UInt)? in
          // Extract build number from tag_name (format: "builds/{version}/{build}")
          let components = release.tag_name.split(separator: "/")
          guard components.count == 3,
            let buildNumber = UInt(components[2])
          else {
            Logger.shared.warning("Invalid tag format: \(release.tag_name)")
            return nil
          }
          return (release, buildNumber)
        }
        .sorted { $0.1 > $1.1 }  // Sort by build number descending
        .map { $0.0 }  // Extract just the Release objects

      // Check if we have any matching releases
      guard !sortedReleases.isEmpty else {
        throw ReleaseNotesError(version: appVersion)
      }

      // Generate combined markdown content
      status = .content(
        MarkdownContent {
          Heading(.level1) {
            "Release Notes TestFlight"
          }
          for release in sortedReleases {
            Heading(.level2) {
              release.name
            }

            Paragraph {
              Code(release.tag_name)
            }

            MarkdownContent {
              convertIssueReferencesToLinks(release.body)
            }
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
      case .content(let content):
        Markdown(content, baseURL: ReleaseNotesViewModel.baseUrl)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding()
      case .error(let error):
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

      .apply {
        if #available(iOS 26.0, *) {
          $0.safeAreaBar(edge: .bottom) {
            Button(.localizable(.ok)) {}
              .frame(maxWidth: .infinity, alignment: .center)
              .font(.title2)
              .padding()
              .glassEffect(.regular.interactive())
              .padding()

          }
        } else {
          $0.safeAreaInset(edge: .bottom) {
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
        }
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
    _model = StateObject(
      wrappedValue: ReleaseNotesViewModel(version: version, appConfiguration: appConfiguration))
  }
}

#Preview("Current") {
  HelperView()
}

#Preview("TestFlight") {
  HelperView(version: AppVersion(version: "1.9.0", build: "170"), appConfiguration: .TestFlight)
}

#Preview("AppStore") {
  HelperView(version: AppVersion(version: "1.7.1", build: "142"), appConfiguration: .AppStore)
}
