//
//  FilterAssembly.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.11.25.
//

import DataModel
import Networking
import SwiftUI

struct FilterAssembly: View {
  @ObservedObject var filterModel: FilterModel

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
      Label("X", systemImage: "ellipsis.circle")
        .labelStyle(.iconOnly)
    }
  }

  @State private var showSearch = false

  var body: some View {
    VStack {
      if #available(iOS 26.0, *) {
        if showSearch {
          SearchBarView(text: $searchText) {
            searchModeMenu
          }
          .padding(.horizontal)
        }
      } else {
        HStack {
          SearchBarViewiOS18(text: $searchText, cancelEnabled: false) {}

          searchModeMenu
        }
        .padding(.horizontal)
      }

      FilterBar()
        .apply {
          if #unavailable(iOS 26.0) {
            $0.padding(.bottom, 3)
          } else {
            $0
          }
        }

      Button("Show") {
        withAnimation(.spring(duration: 0.2)) { showSearch.toggle() }
      }
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

  }
}

#Preview {
  @Previewable @StateObject var filterModel = FilterModel()
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

    .safeAreaInset(edge: .top) {
      FilterAssembly(filterModel: filterModel)
        .environmentObject(store)
        .environmentObject(errorController)
        // @TODO: Is this needed even?
        .environmentObject(connectionManager)
        .environmentObject(filterModel)
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
