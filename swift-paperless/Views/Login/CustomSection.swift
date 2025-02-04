//
//  CustomSection.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 04.02.25.
//

import SwiftUI

struct CustomSection<Content: View, Footer: View, Header: View>: View {
    var content: () -> Content
    var header: (() -> Header)? = nil
    var footer: (() -> Footer)? = nil

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 4) {
            header?()
                .foregroundStyle(.secondary)
                .font(.footnote)
                .textCase(.uppercase)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            content()
                .padding(.horizontal)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .circular)
                        .fill(.background.tertiary)
                )

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

    init(@ViewBuilder content: @escaping () -> Content, footer _: () -> Void, header: @escaping () -> Header) {
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

    init(@ViewBuilder content: @escaping () -> Content, @ViewBuilder footer: @escaping () -> Footer, header _: () -> Void) {
        self.init(content: content, header: nil, footer: footer)
    }
}

#Preview("CustomSection") {
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
    }
    .modifier(BackgroundColorModifier())
}
