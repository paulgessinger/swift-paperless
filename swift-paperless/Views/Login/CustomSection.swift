//
//  CustomSection.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import Common
import SwiftUI

private struct CustomSectionBackgroundKey: EnvironmentKey {
  static let defaultValue: AnyShapeStyle? = nil
}

extension EnvironmentValues {
  var customSectionBackground: AnyShapeStyle? {
    get { self[CustomSectionBackgroundKey.self] }
    set { self[CustomSectionBackgroundKey.self] = newValue }
  }
}

extension View {
  func customSectionBackground<S: ShapeStyle>(_ style: S) -> some View {
    environment(\.customSectionBackground, AnyShapeStyle(style))
  }

  func customSectionBackground(_ style: AnyShapeStyle?) -> some View {
    environment(\.customSectionBackground, style)
  }
}

struct CustomSectionRow<Content: View>: View {
  let content: () -> Content

  @ScaledMetric(relativeTo: .body) private var rowVerticalPadding = 8.0

  init(@ViewBuilder content: @escaping () -> Content) {
    self.content = content
  }

  var body: some View {
    content()
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
      .padding(.vertical, rowVerticalPadding)
  }
}

struct CustomSection<Content: View, Footer: View, Header: View>: View {
  var content: () -> Content
  var header: (() -> Header)? = nil
  var footer: (() -> Footer)? = nil

  @Environment(\.customSectionBackground) private var backgroundStyle

  @SchemeValue(
    light: Color(uiColor: .systemBackground),
    dark: Color(uiColor: .secondarySystemBackground))
  private var solidBackgroundColor

  private var backgroundFill: AnyShapeStyle {
    backgroundStyle ?? AnyShapeStyle(solidBackgroundColor)
  }

  private func sectionBackground(cornerRadius: CGFloat, style: RoundedCornerStyle) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: style)
    return shape.fill(backgroundFill)
  }

  var body: some View {
    VStack(spacing: 4) {
      header?()
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .apply {
          if #available(iOS 26.0, *) {
            $0
              .bold()
          } else {
            $0
              .font(.footnote)
              .textCase(.uppercase)
          }
        }

      content()
        .padding(.horizontal)
        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        .apply {
          if #available(iOS 26.0, *) {
            $0
              .padding(.vertical, 5)
              .background(
                sectionBackground(cornerRadius: 23, style: .continuous)
              )
          } else {
            $0
              .background(
                sectionBackground(cornerRadius: 10, style: .circular)
              )
          }
        }

      footer?()
        .foregroundStyle(.secondary)
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
    .padding()
  }
}

extension CustomSection where Footer == EmptyView {
  init(@ViewBuilder content: @escaping () -> Content, header: @escaping () -> Header) {
    self.init(content: content, header: header, footer: nil)
  }

  init(
    @ViewBuilder content: @escaping () -> Content, footer _: () -> Void,
    header: @escaping () -> Header
  ) {
    self.init(content: content, header: header, footer: nil)
  }
}

extension CustomSection where Footer == EmptyView, Header == EmptyView {
  init(@ViewBuilder content: @escaping () -> Content) {
    self.init(content: content, header: nil, footer: nil)
  }

  init(@ViewBuilder content: @escaping () -> Content, footer _: () -> Void, header _: () -> Void) {
    self.init(content: content, header: nil, footer: nil)
  }
}

extension CustomSection where Header == EmptyView {
  init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer) {
    self.init(content: content, header: nil, footer: footer)
  }

  init(
    @ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer,
    header _: () -> Void
  ) {
    self.init(content: content, header: nil, footer: footer)
  }
}

#Preview("CustomSection") {
  VStack {
    ScrollView(.vertical) {
      CustomSection {
        HStack {
          Text("GO IDENTITY!")
          Text("Right")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } header: {
        Text("head")
      } footer: {
        Text("yo")
      }

      CustomSection {
        VStack(spacing: 0) {
          CustomSectionRow {
            Text("GO IDENTITY!")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
        }
      } header: {
        Text("head")
      } footer: {
        Text("yo")
      }
    }

    Form {
      Section {
        HStack {
          Text("GO IDENTITY!")
          Text("Right")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } header: {
        Text("head")
      } footer: {
        Text("yo")
      }

      Section {
        VStack(spacing: 0) {
          CustomSectionRow {
            Text("GO IDENTITY!")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
          Divider()
          CustomSectionRow {
            Text("Right")
          }
        }
      } header: {
        Text("head")
      } footer: {
        Text("yo")
      }
    }
  }
  .modifier(BackgroundColorModifier())
}
