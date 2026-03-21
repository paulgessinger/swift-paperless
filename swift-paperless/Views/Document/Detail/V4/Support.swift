//
//  Support.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 21.02.26.
//

import Common
import DataModel
import Flow
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
}

struct EditableAspect: View {
  let label: String?
  let systemImage: String
  let transitionID: TransitionID?
  let namespace: Namespace.ID?
  let action: (() -> Void)?
  let showPrivateFallback: Bool
  let accessibilityLabel: String?

  @ScaledMetric(relativeTo: .body)
  private var fontSizeRaw = 15

  private var fontSize: CGFloat {
    min(fontSizeRaw, 20)
  }

  private var pillPadding: CGFloat {
    1 + fontSize / 6
  }

  private var iconPadding: CGFloat {
    2 + fontSize / 6
  }

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.35))
  private var iconBackgroundColor: Color

  @SchemeValue(.editButtonColor)
  private var editButtonColor

  init(
    localized: LocalizedStringResource, systemImage: String, action: (() -> Void)? = nil,
    transitionID: TransitionID? = nil,
    namespace: Namespace.ID? = nil,
    showPrivateFallback: Bool = true,
    accessibilityLabel: String? = nil
  ) {
    self.label = String(localized: localized)
    self.systemImage = systemImage
    self.action = action
    self.transitionID = transitionID
    self.namespace = namespace
    self.showPrivateFallback = showPrivateFallback
    self.accessibilityLabel = accessibilityLabel
  }

  init(
    _ label: String?, systemImage: String, action: (() -> Void)? = nil,
    transitionID: TransitionID? = nil,
    namespace: Namespace.ID? = nil,
    showPrivateFallback: Bool = true,
    accessibilityLabel: String? = nil
  ) {
    self.label = label
    self.systemImage = systemImage
    self.action = action
    self.transitionID = transitionID
    self.namespace = namespace
    self.showPrivateFallback = showPrivateFallback
    self.accessibilityLabel = accessibilityLabel
  }

  private var displayLabel: String? {
    if let label {
      return label
    }
    if showPrivateFallback {
      return String(localized: .permissions(.private))
    }
    return nil
  }

  private var computedAccessibilityLabel: String? {
    accessibilityLabel ?? displayLabel
  }

  var body: some View {
    Button {
      action?()
    } label: {
      HStack {
        Image(systemName: systemImage)
          .resizable()
          .scaledToFit()
          .frame(width: fontSize, height: fontSize)
          .padding(iconPadding)
          .background(Circle().fill(iconBackgroundColor))
          .padding(.vertical, pillPadding)
          .padding(.leading, pillPadding)
        if let displayLabel {
          Text(displayLabel)
            .italic(label == nil && showPrivateFallback)
        }
        Image(systemName: "pencil")
          .foregroundStyle(editButtonColor)
          .padding(.trailing, 2 + fontSize / 2)
      }
      .font(.system(size: fontSize))
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
    .accessibilityLabel(computedAccessibilityLabel ?? "")
    .buttonStyle(.plain)
  }
}

struct DocumentTagsSection: View {
  @SchemeValue(.editButtonColor)
  private var editButtonColor

  @SchemeValue(.backgroundColor)
  private var backgroundColor

  @SchemeValue(light: Color(white: 0.9), dark: Color(white: 0.3))
  private var editButtonBackground

  let tags: [Tag?]
  let action: (() -> Void)?
  let transitionID: TransitionID?
  let namespace: Namespace.ID?

  var body: some View {
    HStack(alignment: .top) {
      Button {
        action?()
      } label: {
        TagsView(
          tags: tags, action: nil,
          content: {
            Label(.localizable(.edit), systemImage: "pencil")
              .foregroundStyle(editButtonColor)
              .apply {
                if tags.isEmpty {
                  $0.labelStyle(.titleAndIcon)
                    .padding(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                } else {
                  $0.labelStyle(.iconOnly)
                    .padding(5)
                }
              }
              .background {
                if tags.isEmpty {
                  Capsule()
                    .fill(backgroundColor)
                } else {
                  Circle()
                    .fill(backgroundColor)
                }
              }
          }
        )
      }
      .buttonStyle(.plain)
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
