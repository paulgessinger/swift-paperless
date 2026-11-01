import AppShared
import AppViews
import MarkdownUI
import SwiftUI

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
      Text(.app(.skip))
    }
    .opacity(isLastPage ? 0 : 1)
    .disabled(isLastPage)
    .animation(.default, value: isLastPage)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal)
    .padding(.vertical, 8)
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

private struct IconTile: View {
  let card: WhatsNewDeck.Card

  /// The symbol comes from published content and may be newer than this OS.
  private var symbol: String {
    UIImage(systemName: card.icon) == nil ? "sparkles" : card.icon
  }

  private var tint: Color {
    switch card.tint {
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

  var body: some View {
    Image(systemName: symbol)
      .font(.title2)
      .foregroundStyle(tint)
      .frame(width: 44, height: 44)
      .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 11))
      .accessibilityHidden(true)
  }
}

private struct CardView: View {
  let card: WhatsNewDeck.Card
  let moreLabel: String

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      IconTile(card: card)

      VStack(alignment: .leading, spacing: 3) {
        Text(verbatim: card.title)
          .font(.headline)
        Text(verbatim: card.text)
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

  private var optIn: Binding<Bool> {
    Binding(
      get: { AppSettings.shared.telemetryOptIn ?? false },
      set: { AppSettings.shared.telemetryOptIn = $0 })
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        CardView(card: card, moreLabel: "See what's sent")

        Toggle(isOn: optIn) {
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

  var body: some View {
    ScrollView {
      Markdown(card.detail ?? "", baseURL: DocumentationLinks.releaseNotes)
        .frame(maxWidth: 540, alignment: .leading)
        .padding()
        .frame(maxWidth: .infinity)
    }
    .navigationTitle(Text(verbatim: card.title))
    .navigationBarTitleDisplayMode(.inline)
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
