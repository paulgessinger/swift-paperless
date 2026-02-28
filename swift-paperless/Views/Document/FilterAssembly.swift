//
//  FilterAssembly.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.11.25.
//

import DataModel
import Networking
import SwiftUI

@available(iOS 26.0, *)
struct FilterAssembly: View {
  var filterModel: FilterModel

  @State private var searchText: String = ""
  @State private var searchTask: Task<Void, Never>?
  private let searchTaskDelay: Duration = .seconds(0.5)

  private var searchModeMenu: some View {
    Menu {
      ForEach(FilterState.SearchMode.allCases, id: \.self) { searchMode in
        if filterModel.filterState.searchMode == searchMode {
          Label(searchMode.localizedName, systemImage: "checkmark")
        } else {
          Button(searchMode.localizedName) {
            filterModel.filterState.searchMode = searchMode
          }
        }
      }

    } label: {
      Label(localized: .localizable(.searchModeSettings), systemImage: "ellipsis.circle")
        .labelStyle(.iconOnly)
        .foregroundStyle(.accentColorLightened)
    }
  }

  @State private var showSearch = false

  var body: some View {
    VStack(spacing: 0) {
      SearchBarView(text: $searchText) {
        searchModeMenu
      }
      .padding(.horizontal)

      FilterBar()
        .padding(.top, 5)
    }
    .opacity(filterModel.ready ? 1.0 : 0.0)
    .animation(.default, value: filterModel.ready)

    .onChange(of: searchText) {
      searchTask?.cancel()

      guard searchText != filterModel.filterState.searchText else { return }

      searchTask = Task {
        do {
          try await Task.sleep(for: searchTaskDelay)
          filterModel.filterState.searchText = searchText
        } catch {}
      }
    }

    .task {
      searchText = filterModel.filterState.searchText
    }

    .onChange(of: filterModel.filterState.searchText) {
      // If we clear the filter state, the search text also needs to be cleared here
      if searchText != filterModel.filterState.searchText {
        searchText = filterModel.filterState.searchText
      }
    }

    .background(
      Rectangle()
        .fill(
          Material.ultraThinMaterial
        )
        .mask {
          LinearGradient(
            colors: [
              Color.black,
              Color.black,
              Color.black.opacity(0.4),
              Color.black.opacity(0),
            ], startPoint: .top, endPoint: .bottom)

        }

        .ignoresSafeArea(.container, edges: .top)
    )
  }
}

@available(iOS 26.0, *)
#Preview {
  @Previewable @State var filterModel = FilterModel()
  @Previewable @StateObject var store = DocumentStore(repository: PreviewRepository())
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @StateObject var connectionManager = ConnectionManager()
  @Previewable @State var searchText = ""

  NavigationStack {
    List {
      ForEach(0..<100) { i in
        Text("Item \(i)")
      }
    }

    .apply {
      $0.scrollEdgeEffectHidden(true, for: .top)
    }

    .safeAreaInset(edge: .top) {
      FilterAssembly(filterModel: filterModel)
        .environmentObject(store)
        .environmentObject(errorController)
        // @TODO: Is this needed even?
        .environmentObject(connectionManager)
        .environment(filterModel)
    }

    .toolbarTitleMenu {
      Button("Select") {}
      Button("Another") {}
    }

    .toolbar {
      ToolbarItem(placement: .navigationBarLeading) {
        Image(systemName: "doc.text.magnifyingglass")
      }

      ToolbarItem(placement: .navigationBarTrailing) {
        Image(systemName: "plus")
      }
    }

    .navigationTitle("Documents")
    .navigationBarTitleDisplayMode(.inline)
  }
}
