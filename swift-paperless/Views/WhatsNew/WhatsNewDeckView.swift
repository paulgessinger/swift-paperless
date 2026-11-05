import AppShared
import AppViews
import Common
import MarkdownUI
import SwiftUI

extension EnvironmentValues {
  /// What relative images and links in a deck resolve against.
  @Entry var whatsNewBaseURL: URL = DocumentationLinks.releaseNotes
}

struct WhatsNewDeckView: View {
  let deck: WhatsNewDeck
  var finishLabel = String(localized: .app(.done))
  let onDismiss: () -> Void

  @State private var page = 0

  private var isLastPage: Bool {
    page >= deck.pages.count - 1
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $page) {
        ForEach(deck.pages.indices, id: \.self) { index in
          PageView(page: deck.pages[index])
            .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .safeAreaInset(edge: .top) {
        if deck.pages.count > 1 {
          skipButton
        }
      }
      .safeAreaInset(edge: .bottom) {
        footer
      }
      .toolbar(.hidden, for: .navigationBar)
    }
    .tipJarLinks()
  }

  /// Fades rather than leaving the layout: changing the navigation bar while
  /// `page` flips mid-swipe cancels the swipe.
  private var skipButton: some View {
    Button {
      onDismiss()
    } label: {
      // The bare word is too small a target once it's out of the toolbar.
      Text(.app(.skip))
        .padding(.vertical, 10)
        .padding(.trailing, 24)
        .contentShape(Rectangle())
    }
    .opacity(isLastPage ? 0 : 1)
    .disabled(isLastPage)
    .animation(.default, value: isLastPage)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
  }

  private var footer: some View {
    VStack(spacing: 12) {
      if deck.pages.count > 1 {
        HStack(spacing: 8) {
          ForEach(deck.pages.indices, id: \.self) { index in
            Circle()
              .fill(index == page ? Color.accentColor : Color.secondary.opacity(0.3))
              .frame(width: 7, height: 7)
          }
        }
        .accessibilityHidden(true)
      }

      Button {
        if isLastPage {
          onDismiss()
        } else {
          withAnimation { page += 1 }
        }
      } label: {
        Text(verbatim: isLastPage ? finishLabel : String(localized: .app(.next)))
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .frame(maxWidth: 540)
    .padding()
  }
}

private struct PageView: View {
  let page: WhatsNewDeck.Page

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        VStack(spacing: 6) {
          Text(verbatim: page.title)
            .font(.largeTitle)
            .bold()
          if let subtitle = page.subtitle {
            Text(verbatim: subtitle)
              .font(.title3)
              .foregroundStyle(.secondary)
          }
        }
        .multilineTextAlignment(.center)

        VStack(alignment: .leading, spacing: 20) {
          ForEach(page.blocks.indices, id: \.self) { index in
            switch page.blocks[index] {
            case .card(let card):
              CardView(card: card, moreLabel: String(localized: .app(.learnMore)))
            case .tip(let card):
              TipBlock(card: card)
            case .telemetry(let card):
              if AppFeatures.enabled(.telemetry) {
                TelemetryBlock(card: card)
              }
            }
          }
        }
      }
      .frame(maxWidth: 540)
      .padding()
      .frame(maxWidth: .infinity)
    }
  }
}

extension WhatsNewDeck.Card {
  fileprivate var tintColor: Color {
    switch tint {
    case "blue": .blue
    case "indigo": .indigo
    case "orange": .orange
    case "pink": .pink
    case "purple": .purple
    case "red": .red
    case "teal": .teal
    default: .accentColor
    }
  }

  /// Inline Markdown, so a card's line can carry a link. Trimmed because a
  /// YAML block scalar ends in a newline.
  fileprivate var attributedText: AttributedString {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return
      (try? AttributedString(
        markdown: text,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }
}

private struct IconTile: View {
  let card: WhatsNewDeck.Card
  var size: CGFloat = 44

  /// The symbol comes from published content and may be newer than this OS.
  private var symbol: String {
    UIImage(systemName: card.icon) == nil ? "sparkles" : card.icon
  }

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5))
      .foregroundStyle(card.tintColor)
      .frame(width: size, height: size)
      .background(card.tintColor.opacity(0.15), in: RoundedRectangle(cornerRadius: size / 4))
      .accessibilityHidden(true)
  }
}

private struct CardView: View {
  let card: WhatsNewDeck.Card
  let moreLabel: String

  @Environment(\.whatsNewBaseURL) private var baseURL

  var body: some View {
    VStack(spacing: 14) {
      if let url = card.imageURL(relativeTo: baseURL) {
        CardImage(url: url)
      }
      row
    }
  }

  private var row: some View {
    HStack(alignment: .top, spacing: 14) {
      IconTile(card: card)

      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: card.title)
          .font(.headline)
        Text(card.attributedText)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        if card.detail != nil {
          NavigationLink {
            DetailView(card: card)
          } label: {
            Text(verbatim: moreLabel)
              .font(.subheadline)
          }
          .padding(.top, 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}

/// Holds its height while loading so the page doesn't jump, and collapses if the
/// image can't be loaded: the card still reads fine without it.
private struct CardImage: View {
  let url: URL
  var height: CGFloat = 140

  @State private var failed = false

  var body: some View {
    if !failed {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .scaledToFit()
        case .failure:
          Color.clear.onAppear { failed = true }
        default:
          ProgressView()
        }
      }
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .accessibilityHidden(true)
    }
  }
}

private struct TipBlock: View {
  let card: WhatsNewDeck.Card

  var body: some View {
    VStack(spacing: 14) {
      CardView(card: card, moreLabel: String(localized: .app(.learnMore)))
      TipJarQuickOptions()
    }
    .padding()
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
  }
}

/// Records the choice in ``AppSettings/telemetryOptIn``. The text is a placeholder
/// until telemetry exists, so it stays out of the string catalogs.
private struct TelemetryBlock: View {
  let card: WhatsNewDeck.Card

  @Bindable private var appSettings = AppSettings.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        CardView(card: card, moreLabel: "See what's sent")

        Toggle(isOn: Binding($appSettings.telemetryOptIn, default: false)) {
          Text(verbatim: card.title)
        }
        .labelsHidden()
      }

      Text(verbatim: "Change this anytime in Settings.")
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
    .padding()
    .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 16))
  }
}

private struct DetailView: View {
  let card: WhatsNewDeck.Card

  @Environment(\.whatsNewBaseURL) private var baseURL

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        header
        Divider()
        Markdown(card.detail ?? "", baseURL: baseURL)
          .markdownTheme(.whatsNew(tint: card.tintColor))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: 540)
      .padding()
      .frame(maxWidth: .infinity)
    }
    .navigationBarTitleDisplayMode(.inline)
  }

  /// Repeats the card, so the screen reads as the card opened up.
  private var header: some View {
    VStack(spacing: 12) {
      if let url = card.imageURL(relativeTo: baseURL) {
        CardImage(url: url, height: 120)
      } else {
        IconTile(card: card, size: 72)
      }
      Text(verbatim: card.title)
        .font(.title)
        .bold()
      Text(card.attributedText)
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .multilineTextAlignment(.center)
    .padding(.top, 8)
  }
}

extension Theme {
  /// Roomier than `.basic`, with headings and links in the card's tint and
  /// block quotes drawn as callouts.
  @MainActor
  fileprivate static func whatsNew(tint: Color) -> Theme {
    Theme.basic
      .link {
        ForegroundColor(tint)
      }
      .heading3 { configuration in
        configuration.label
          .markdownMargin(top: .rem(1.5), bottom: .rem(0.5))
          .markdownTextStyle {
            FontWeight(.semibold)
            FontSize(.em(1.15))
            ForegroundColor(tint)
          }
      }
      .paragraph { configuration in
        configuration.label
          .fixedSize(horizontal: false, vertical: true)
          .relativeLineSpacing(.em(0.25))
          .markdownMargin(top: .zero, bottom: .em(1))
      }
      .listItem { configuration in
        configuration.label
          .markdownMargin(top: .em(0.4))
      }
      .blockquote { configuration in
        configuration.label
          .relativeLineSpacing(.em(0.2))
          .padding(14)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
          .markdownMargin(top: .zero, bottom: .em(1))
      }
      .image { configuration in
        configuration.label
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .markdownMargin(top: .em(0.5), bottom: .em(1))
      }
  }
}

extension WhatsNewDeck {
  // swift-format-ignore
  static let sample = try! WhatsNewDeck(json: Data(#"""
    {
      "version": "1.10.0",
      "pages": [
        {
          "title": "What's new in 1.10",
          "subtitle": "Document details",
          "blocks": [
            {
              "type": "card",
              "icon": "doc.text.image",
              "title": "Redesigned detail screen",
              "text": "Clearer metadata and sheet-based editing.",
              "detail": "The document detail screen has been completely redesigned with clearer metadata and sheet-based editing for tags, correspondent, document type, storage path, dates, ASN, custom fields, and owner.\n\n- Horizontal PDF paging with a page indicator\n- In-document search in the full-screen preview\n- Delete documents from the detail screen\n\nEnjoying the app? [Leave a tip](https://swift-paperless.app/tip)."
            },
            {
              "type": "card",
              "icon": "magnifyingglass",
              "tint": "blue",
              "title": "In-document search",
              "text": "Search right in the full-screen preview."
            },
            {
              "type": "card",
              "icon": "note.text",
              "tint": "orange",
              "title": "Note counts",
              "text": "See how many notes a document has."
            }
          ]
        },
        {
          "title": "Everything else",
          "blocks": [
            {
              "type": "card",
              "icon": "rectangle.split.3x1",
              "tint": "indigo",
              "title": "Multi-column iPad layout",
              "text": "Much better use of the larger screen."
            },
            {
              "type": "card",
              "icon": "tag",
              "tint": "teal",
              "title": "Nested tags",
              "text": "Support for hierarchical tags."
            },
            {
              "type": "card",
              "icon": "plus.circle",
              "title": "Quick add",
              "text": "Create tags and types while searching."
            }
          ]
        },
        {
          "title": "Help Swift Paperless",
          "subtitle": "Two optional ways to help.",
          "blocks": [
            {
              "type": "tip",
              "icon": "heart.fill",
              "tint": "red",
              "title": "Leave a tip",
              "text": "Placeholder text about supporting development."
            },
            {
              "type": "telemetry",
              "icon": "chart.bar",
              "title": "Share anonymous usage",
              "text": "Placeholder text about what is shared.",
              "detail": "Placeholder: the description of what is sent gets written with the telemetry implementation."
            }
          ]
        }
      ]
    }
    """#.utf8))
}

#Preview {
  WhatsNewDeckView(deck: .sample) {}
}

#if DEBUG
  private let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // WhatsNew
    .deletingLastPathComponent()  // Views
    .deletingLastPathComponent()  // swift-paperless
    .deletingLastPathComponent()

  /// The newest deck `scripts/whats_new.py` wrote into the repo's `site/whats_new`.
  private func generatedDeck() -> WhatsNewDeck? {
    let directory = repoRoot.appending(path: "site/whats_new")
    let files =
      (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
      ?? []
    let newest =
      files
      .compactMap { file in
        Version(file.deletingPathExtension().lastPathComponent).map { ($0, file) }
      }
      .max { $0.0 < $1.0 }
    return newest.flatMap { try? WhatsNewDeck(json: Data(contentsOf: $0.1)) }
  }

  #Preview("Generated") {
    if let deck = generatedDeck() {
      // Images in the repo, which may not be on the site yet.
      WhatsNewDeckView(deck: deck) {}
        .environment(
          \.whatsNewBaseURL,
          repoRoot.appending(path: "docs/release_notes/", directoryHint: .isDirectory))
    } else {
      Text(
        verbatim: "Run `uv run scripts/whats_new.py build docs/release_notes site/whats_new` first."
      )
      .padding()
    }
  }
#endif
