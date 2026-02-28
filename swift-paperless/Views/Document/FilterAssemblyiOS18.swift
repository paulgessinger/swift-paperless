//
//  FilterAssembly.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 29.11.25.
//

import DataModel
import Networking
import SwiftUI

struct FilterAssemblyiOS18: View {
  var filterModel: FilterModel

  @State private var searchText: String = ""
  @State private var searchTask: Task<Void, Never>?
  private let searchTaskDelay: Duration = .seconds(0.5)

  var body: some View {
    VStack {
      HStack {
        SearchBarViewiOS18(text: $searchText, cancelEnabled: false) {}

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
        }
      }
      .padding(.horizontal)

      FilterBar()
        .padding(.bottom, 3)
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

    .background(
      Rectangle()
        .fill(
          Material.bar
        )
        .ignoresSafeArea(.container, edges: .top)
    )

    .overlay(alignment: .bottom) {
      Rectangle()
        .fill(.gray)
        .frame(height: 1, alignment: .bottom)
    }
  }
}

#Preview {
  @Previewable @State var filterModel = FilterModel()
  @Previewable @StateObject var store = DocumentStore(repository: PreviewRepository())
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @StateObject var connectionManager = ConnectionManager()

  NavigationStack {
    List {
      ForEach(0..<100) { i in
        Text("Item \(i)")
      }
    }

    .safeAreaInset(edge: .top) {
      FilterAssemblyiOS18(filterModel: filterModel)
        .environmentObject(store)
        .environmentObject(errorController)
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
