//
//  Support.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import AppShared
import Common
import DataModel
import SwiftUI

extension Common.SchemeToken where Value == Color {
  fileprivate static var editButtonColor: Self {
    .init(light: Color(white: 0.3), dark: Color(white: 0.5))
  }

  fileprivate static var backgroundColor: Self {
    .init(light: Color(white: 0.97), dark: Color(white: 0.2))
  }
}

enum TransitionID: Hashable {
  case doc
  case tags
  case date
  case asn
  case correspondent
  case documentType
  case storagePath
  case owner
  case metadata
  case notes
  case title
  case customFields
}

enum AspectLabel {
  case text(String)
  case notAssigned
  case `private`

  var displayText: String? {
    switch self {
    case .text(let value): value
    case .private: String(localized: .permissions(.private))
    case .notAssigned: nil
    }
  }

  var isPrivate: Bool {
    if case .private = self { return true }
    return false
  }
}

struct EditableAspect: View {
  let title: LocalizedStringResource?
  let label: AspectLabel
  let systemImage: String
  let transitionID: TransitionID?
  let namespace: Namespace.ID?
  let action: (() -> Void)?
  let enabled: Bool

  @ScaledMetric(relativeTo: .body)
  private var fontSizeRaw = 15

  @ScaledMetric(relativeTo: .body)
  private var iconDiameter: CGFloat = 32

  private var fontSize: CGFloat {
    min(fontSizeRaw, 20)
  }

  private var pillPadding: CGFloat {
    2 + fontSize / 6
  }

  private var iconImagePadding: CGFloat {
    iconDiameter * 0.22
  }

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.35))
  private var iconBackgroundColor: Color

  @SchemeValue(.editButtonColor)
  private var editButtonColor

  init(
    title: LocalizedStringResource? = nil,
    label: AspectLabel,
    systemImage: String,
    action: (() -> Void)? = nil,
    transitionID: TransitionID? = nil,
    namespace: Namespace.ID? = nil,
    enabled: Bool = true
  ) {
    self.title = title
    self.label = label
    self.systemImage = systemImage
    self.action = action
    self.transitionID = transitionID
    self.namespace = namespace
    self.enabled = enabled
  }

  private var accessibilityText: Text {
    if let title {
      Text(title) + Text(verbatim: ": ") + Text(label.displayText ?? "")
    } else {
      Text(label.displayText ?? "")
    }
  }

  var body: some View {
    Button {
      action?()
    } label: {
      HStack(spacing: 0) {
        ZStack {
          Circle().fill(iconBackgroundColor)
          Image(systemName: systemImage)
            .resizable()
            .scaledToFit()
            .padding(iconImagePadding)
        }
        .frame(width: iconDiameter, height: iconDiameter)
        .padding(.vertical, pillPadding)
        .padding(.leading, pillPadding)

        VStack(alignment: .leading, spacing: 1) {
          if let title {
            Text(title)
              .font(.caption2)
              .fontWeight(.semibold)
              .textCase(.uppercase)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          Text(label.displayText ?? "—")
            .italic(label.isPrivate)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .padding(.leading, 8)
        .padding(.vertical, 2)

        Spacer(minLength: 8)

        Image(systemName: enabled ? "pencil" : "lock.fill")
          .foregroundStyle(editButtonColor)
          .padding(.trailing, 2 + fontSize / 2)
      }
      .font(.system(size: fontSize))
      .frame(maxWidth: .infinity)
      .background {
        Capsule()
          .fill(backgroundColor)
      }
      .dynamicTypeSize(...DynamicTypeSize.large)
      .apply {
        if let transitionID, let namespace {
          $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
        } else {
          $0
        }
      }
    }
    .accessibilityLabel(accessibilityText)
    .buttonStyle(.plain)
    .allowsHitTesting(enabled)
  }
}

struct DocumentTagsSection: View {
  @SchemeValue(.editButtonColor)
  private var editButtonColor

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.3))
  private var editButtonBackground

  @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 14

  let tags: [Tag?]
  let action: (() -> Void)?
  let transitionID: TransitionID?
  let namespace: Namespace.ID?
  var enabled: Bool = true

  var body: some View {
    HStack(alignment: .top) {
      Button {
        action?()
      } label: {
        TagsView(
          tags: tags, action: nil,
          content: {
            if tags.isEmpty {
              Text(.app(.createDocumentNoTags))
                .foregroundStyle(.secondary)
            }
            Image(systemName: enabled ? "pencil" : "lock.fill")
              .resizable()
              .scaledToFit()
              .frame(width: iconSize, height: iconSize)
              .foregroundStyle(editButtonColor)
              .padding(iconSize / 3 + 2)
              .background(Circle().fill(backgroundColor))
          }
        )
      }
      .buttonStyle(.plain)
      .allowsHitTesting(enabled)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .dynamicTypeSize(...DynamicTypeSize.large)
    .apply {
      if let transitionID, let namespace {
        $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
      } else {
        $0
      }
    }
  }
}

struct DocumentTitleView: View {
  let title: String
  let transitionID: TransitionID?
  let namespace: Namespace.ID?
  let action: () -> Void
  var enabled: Bool = true

  private let lineLimit = 3

  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @State private var isExpanded = false
  @State private var isTruncated = false

  // Truncation + the "More" button only make sense on compact (iPhone). On
  // iPad the inspector is wide enough — and resizable — that any line cap
  // is misleading; just let the title flow as long as it needs.
  private var truncates: Bool { horizontalSizeClass != .regular }

  @SchemeValue(.editButtonColor)
  private var editButtonColor

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  private var titleText: Text {
    Text(title)
      .font(.title2)
      .fontWeight(.semibold)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 8) {
        Button(action: action) {
          titleText
            .lineLimit(truncates && !isExpanded ? lineLimit : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              // Skip the truncation measurement entirely on iPad — the
              // measurement only fires on appear / title change, so it
              // can't keep up with inspector resizing and would otherwise
              // leave the "More" button stuck visible.
              Group {
                if truncates {
                  GeometryReader { displayedProxy in
                    titleText
                      .fixedSize(horizontal: false, vertical: true)
                      .frame(width: displayedProxy.size.width, alignment: .leading)
                      .hidden()
                      .background(
                        GeometryReader { fullProxy in
                          Color.clear.onAppear {
                            isTruncated =
                              fullProxy.size.height > displayedProxy.size.height + 1
                          }
                          .onChange(of: title) {
                            isTruncated =
                              fullProxy.size.height > displayedProxy.size.height + 1
                          }
                        }
                      )
                  }
                }
              }
            )
        }
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .allowsHitTesting(enabled)
        .apply {
          if let transitionID, let namespace {
            $0.backport.matchedTransitionSource(id: transitionID, in: namespace)
          } else {
            $0
          }
        }

        if enabled {
          Button(action: action) {
            Image(systemName: "pencil")
              .foregroundStyle(editButtonColor)
              .font(.callout)
              .padding(6)
              .background(Circle().fill(backgroundColor))
          }
          .buttonStyle(.plain)
          .padding(.top, 3)
        } else {
          Image(systemName: "lock.fill")
            .foregroundStyle(editButtonColor)
            .font(.callout)
            .padding(6)
            .background(Circle().fill(backgroundColor))
            .padding(.top, 3)
        }
      }

      if truncates && (isTruncated || isExpanded) {
        Button {
          withAnimation(.spring(duration: 0.15)) {
            isExpanded.toggle()
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "chevron.down")
              .rotationEffect(isExpanded ? .degrees(180) : .zero)
            Text(.app(.more))
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 6)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Pull the row up visually *and* shift its hit area — `.offset` only
        // moves the rendering, so the original button frame stayed at the
        // un-offset position and the visible chevron tapped on nothing.
        .padding(.top, -5)
      }
    }
  }
}

// MARK: - Suggestions

struct SuggestionPill: View {
  let text: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(text)
        .font(.footnote)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: 200, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(.accent.opacity(0.15)))
        .foregroundStyle(.accent)
    }
    .buttonStyle(.plain)
  }
}

struct SuggestionsRow<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    Divider()
    CustomSectionRow {
      HFlow {
        content()
      }
    }
  }
}
