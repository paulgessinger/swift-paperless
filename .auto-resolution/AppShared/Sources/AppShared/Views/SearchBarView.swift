//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
public struct SearchBarView<Content: View>: View {
  @Binding public var text: String
  public var isLoading: Bool = false
  public let content: () -> Content

  public init(
    text: Binding<String>, isLoading: Bool = false,
    @ViewBuilder content: @escaping () -> Content
  ) {
    self._text = text
    self.isLoading = isLoading
    self.content = content
  }

  @FocusState private var focused: Bool
  @State private var showCancel: Bool = false

  public var body: some View {
    GlassEffectContainer(spacing: 0) {
      HStack {
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
          TextField(
            text: $text,
            label: {
              Text(.app(.search))
            }
          )
          .focused($focused)
          ProgressView()
            .controlSize(.regular)
            .opacity(isLoading ? 1 : 0)
            .animation(.default, value: isLoading)
        }
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .frame(height: 45)
        .glassEffect(.regular.interactive())

        if showCancel {
          Button {
            focused = false
            text = ""
          } label: {
            Label(localized: .app(.cancel), systemImage: "xmark")
              .labelStyle(.iconOnly)
              .foregroundStyle(Color("AccentColorLightened"))
          }
          .font(.title2)
          .frame(width: 45, height: 45)
          .glassEffect(.regular.interactive(), in: .circle)
        }

        content()
          .font(.title2)
          .frame(width: 45, height: 45)
          .glassEffect(.regular.interactive(), in: .circle)
      }
    }

    .onChange(of: text) {
      withAnimation {
        showCancel = !text.isEmpty
      }
    }

    .task {
      showCancel = !text.isEmpty
    }
  }
}

@available(iOS 26.0, *)
extension SearchBarView where Content == EmptyView {
  public init(text: Binding<String>, isLoading: Bool = false) {
    self._text = text
    self.isLoading = isLoading
    self.content = { EmptyView() }
  }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview("SearchBarView") {
  @Previewable @State var text = ""

  NavigationStack {
    List {
      ForEach(0..<30) { i in
        Text("Item \(i)")
      }
    }

    .navigationTitle("Hallo")
    .toolbar {
      ToolbarItem {
        Button("go") {}
      }
    }

    .safeAreaInset(edge: .top) {
      //            HStack {
      SearchBarView(text: $text) {
        Button("Go") {}
      }
      .padding(.horizontal)
    }
  }
}
