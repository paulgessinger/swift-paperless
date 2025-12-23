//
//  SearchBarView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 12.03.23.
//

import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct SearchBarView<Content: View>: View {
  @Binding var text: String
  let content: () -> Content

  @FocusState private var focused: Bool
  @State private var showCancel: Bool = false

  var body: some View {
    GlassEffectContainer(spacing: 0) {
      HStack {
        HStack(spacing: 12) {
          Image(systemName: "magnifyingglass")
          TextField(
            text: $text,
            label: {
              Text(.localizable(.search))
            }
          )
          .focused($focused)
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
            Label(localized: .localizable(.cancel), systemImage: "xmark")
              .labelStyle(.iconOnly)
              .foregroundStyle(.accentColorLightened)
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
  init(text: Binding<String>) {
    self._text = text
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
