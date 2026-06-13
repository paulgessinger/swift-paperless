//
//  DocumentList.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 16.07.23.
//

import AppShared
import DataModel
import Foundation
import Networking
import Nuke
import Persistence
import SwiftUI
import os

extension Document {
  /// A throwaway document used only to render a redacted skeleton row for a
  /// `DocumentEntry.skeleton` (the real object isn't cached). Never stored; the
  /// redaction hides the placeholder text.
  fileprivate static func skeletonPlaceholder(id: UInt) -> Document {
    Document(id: id, title: "Loading document title", created: .now, tags: [])
  }
}

struct LoadingDocumentList: View {
  @State private var documents: [Document] = []
  @State private var store = DocumentStore.preview()

  var body: some View {
    List {
      Section {
        ForEach(documents, id: \.self) { document in
          DocumentCell(document: document, store: store)
            .redacted(reason: .placeholder)
            .padding(.horizontal)
            .padding(.vertical)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .alignmentGuide(.listRowSeparatorLeading) { _ in 15 }
        }
      }
      .listSectionSeparator(.hidden)
    }
    .listStyle(.plain)
    .task {
      documents = await PreviewRepository().documents(filter: .default).fetch(limit: 10)
    }
  }
}

struct DocumentList: View {
  var store: DocumentStore
  var onSelect: (Document) -> Void
  var filterModel: FilterModel
  @Binding var isFetching: Bool
  // iPad split-view: highlights the row matching the selected detail doc.
  // Nil on iPhone (push-based navigation needs no list-side highlight).
  var selectedDocumentID: UInt?

  @State private var documentToDelete: Document?

  @State private var viewModel: DocumentListViewModel

  @EnvironmentObject private var errorController: ErrorController

  @ObservedObject private var appSettings = AppSettings.shared

  init(
    store: DocumentStore, onSelect: @escaping (Document) -> Void, filterModel: FilterModel,
    errorController: ErrorController, isFetching: Binding<Bool>,
    selectedDocumentID: UInt? = nil
  ) {
    self.store = store
    self.onSelect = onSelect
    self.filterModel = filterModel
    _isFetching = isFetching
    self.selectedDocumentID = selectedDocumentID
    _viewModel = State(
      initialValue: DocumentListViewModel(
        store: store,
        filterState: filterModel.filterState,
        errorController: errorController))
  }

  struct Cell: View {
    var store: DocumentStore
    var document: Document
    var onSelect: (Document) -> Void
    var documentDeleteConfirmation: Bool
    @Binding var documentToDelete: Document?
    var viewModel: DocumentListViewModel
    var isSelected: Bool

    @EnvironmentObject private var errorController: ErrorController
    @Environment(\.colorScheme) private var colorScheme

    private var userCanChange: Bool {
      store.userCanChange(document: document)
    }

    private var userCanDelete: Bool {
      store.userCanDelete(document: document)
    }

    private var canRemoveInboxTags: Bool {
      userCanChange && viewModel.hasInboxTags(document: document)
    }

    private func onDeleteButtonPressed() {
      if documentDeleteConfirmation {
        documentToDelete = document
      } else {
        Task { [store = self.store, document = self.document] in
          do {
            try await store.deleteDocument(document)
          } catch {
            Logger.shared.error("Error deleting document: \(error)")
            errorController.push(error: error)
          }
        }
      }
    }

    var body: some View {
      DocumentCell(document: document, store: store)
        .contentShape(Rectangle())

        .padding(.horizontal)
        .padding(.vertical)
        .listRowBackground(
          Group {
            if isSelected {
              // Bump opacity in dark mode so the accent tint stays
              // visible against the darker chrome of the row backdrop.
              // Rendered as the row background (not inside the cell)
              // so it stays clipped to the row during swipe actions.
              RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.15))
                .padding(.horizontal, 8)
            } else {
              Color.clear
            }
          }
        )
        .onTapGesture {
          store.preloadThumbnail(for: document)
          onSelect(document)
        }

        .swipeActions(edge: .leading) {
          if canRemoveInboxTags {
            Button {
              Task { await viewModel.removeInboxTags(document: document) }
            } label: {
              Label(String(localized: .app(.tagsRemoveInbox)), systemImage: "tray")
            }
            .tint(.accentColor)
          }
        }

        .swipeActions(edge: .trailing) {
          if userCanDelete {
            Button(role: documentDeleteConfirmation ? .none : .destructive) {
              onDeleteButtonPressed()
            } label: {
              Label(String(localized: .app(.delete)), systemImage: "trash")
            }
            .tint(.red)
          }
        }

        .contextMenu {
          Button {
            store.preloadThumbnail(for: document)
            onSelect(document)
          } label: {
            Label(String(localized: .app(.edit)), systemImage: "pencil")
          }

          if canRemoveInboxTags {
            Button {
              Task { await viewModel.removeInboxTags(document: document) }
            } label: {
              Label(String(localized: .app(.tagsRemoveInbox)), systemImage: "tray")
            }
          }

          if userCanDelete {
            Button(role: .destructive) {
              onDeleteButtonPressed()
            } label: {
              Label(String(localized: .app(.delete)), systemImage: "trash")
            }
          }

        } preview: {
          PopupDocumentPreview(document: document)
            .environment(store)
        }

        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }
  }

  private func onReceiveEvent(event: DocumentStore.Event) {
    switch event {
    case .deleted, .changed, .changeReceived:
      // Source-of-truth: a mutation write-throughs to the DB and the document
      // observation repaints the list in place (a delete cascades out of every
      // query_order). Nothing to do here.
      break
    case .repositoryWillChange:
      filterModel.ready = false
      viewModel.ready = false
    case .repositoryChanged:
      Task {
        await viewModel.reload()
      }
      Task {
        filterModel.filterState.clear()
        try? await Task.sleep(for: .seconds(0.5))
        filterModel.ready = true
      }
    case .taskError(let task):
      errorController.push(
        message: String(localized: .tasks(.errorNotificationTitle)),
        details: task.localizedResult)
    }
  }

  func refresh() async {
    await viewModel.refresh(userInitiated: true)
  }

  var body: some View {
    VStack {
      if !viewModel.ready {
        LoadingDocumentList()
      } else if viewModel.noPermissions {
        NoPermissionsView(for: Document.self)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          .refreshable {
            await Task {
              await refresh()
            }.value
          }
      } else {
        let documents = viewModel.documents
        if documents.isEmpty {
          // No rows yet: distinguish "still filling" (cold cache + a fill in
          // flight, or the server reports a non-empty count) from a genuinely
          // empty result, so we don't flash "No documents" during the fill.
          if viewModel.isFetching || (viewModel.totalCount ?? 0) > 0 {
            LoadingDocumentList()
          } else {
            NoDocumentsView(filtering: filterModel.filterState.filtering)
              .equatable()
              .refreshable {
                await Task {
                  await refresh()
                }.value
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
          }
        } else {
          ScrollViewReader { proxy in
            List {
              Section {
                ForEach(Array(zip(documents.indices, documents)), id: \.1.id) { idx, entry in
                  Group {
                    switch entry {
                    case .loaded(let document):
                      Cell(
                        store: store,
                        document: document,
                        onSelect: onSelect,
                        documentDeleteConfirmation: appSettings.documentDeleteConfirmation,
                        documentToDelete: $documentToDelete,
                        viewModel: viewModel,
                        isSelected: document.id == selectedDocumentID
                      )
                    case .skeleton(let id):
                      // Membership is known but the object isn't cached yet
                      // (offline, or pending the next delta). A non-interactive
                      // redacted placeholder, matching the loaded-row layout.
                      DocumentCell(document: .skeletonPlaceholder(id: id), store: store)
                        .padding(.horizontal)
                        .padding(.vertical)
                        .redacted(reason: .placeholder)
                    }
                  }
                  .id(entry.id)

                  .alignmentGuide(.listRowSeparatorLeading) { _ in 15 }

                  .task {
                    // Pure local windowing: grow the observed prefix. No network.
                    viewModel.fetchMoreIfNeeded(currentIndex: idx)
                  }
                }
              }
              .listSectionSeparator(.hidden)
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .bottom, spacing: 0) {
              DocumentCountPill(total: viewModel.totalCount)
            }
            // Scroll the selected row into view on iPad when selection
            // changes externally (e.g., from a deep link). `initial: true`
            // catches the freshly-mounted case where selectedDocumentID was
            // set before the list rendered.
            .onChange(of: selectedDocumentID, initial: true) { _, id in
              guard let id else { return }
              withAnimation {
                proxy.scrollTo(id, anchor: .center)
              }
            }
          }
        }
      }
    }
    .animation(.default, value: viewModel.ready)
    .animation(.default, value: viewModel.noPermissions)

    .onChange(of: filterModel.filterState) { _, filter in
      Task {
        await viewModel.refresh(filter: filter)
      }
    }

    .onChange(of: viewModel.isFetching) { _, fetching in
      isFetching = fetching
    }

    // @TODO: Re-evaluate if we want an animation here
    .animation(.default, value: viewModel.documents)

    .refreshable {
      await Task {
        await refresh()
      }.value
    }

    .task {
      await viewModel.load()
    }

    .onEvent(from: store.events, perform: onReceiveEvent)

    // @FIXME: This somehow causes ERROR: not found in table Localizable of bundle CFBundle 0x600001730200 empty string
    .confirmationDialog(
      unwrapping: $documentToDelete,
      title: { _ in String(localized: .app(.documentDelete)) },
      actions: { $item in
        let document = item
        Button(role: .destructive) {
          Task {
            do {
              try await store.deleteDocument(document)
            } catch {
              Logger.shared.error("Error deleting document: \(error)")
              errorController.push(error: error)
            }
          }
        } label: {
          Text(.app(.documentDelete))
        }
        Button(role: .cancel) {
          documentToDelete = nil
        } label: {
          Text(.app(.cancel))
        }
      },
      message: { $item in
        let document = item
        Text(.app(.deleteDocumentName(document.title)))
      })
  }
}

private struct NoDocumentsView: View, Equatable {
  var filtering: Bool

  // Workaround to make SwiftUI call the == func to skip rerendering this view
  @State private var dummy = 5

  var body: some View {
    ScrollView(.vertical) {
      ContentUnavailableView {
        Label(String(localized: .app(.noDocuments)), systemImage: "tray.fill")
      } description: {
        if filtering {
          Text(.app(.noDocumentsDescriptionFilter))
        }
      }

      .padding(.top, 40)
    }
  }

  nonisolated
    static func == (_: NoDocumentsView, _: NoDocumentsView) -> Bool
  {
    true
  }
}

private struct DocumentCountPill: View {
  let total: UInt?

  var body: some View {
    if let total, total > 0 {
      Text(.app(.documentCountIndicator(Int(total))))
        .font(.caption2.monospacedDigit())
        .fontWeight(.semibold)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .backport.glassEffect(
          .regular, in: Capsule(), orFill: .ultraThinMaterial
        )
        .contentTransition(.numericText())
        .animation(.default, value: total)
    }
  }
}

private struct NoPermissionsViewDocument: View {
  var body: some View {
    ScrollView(.vertical) {
      ContentUnavailableView {
        Label(String(localized: .app(.requestErrorForbidden)), systemImage: "lock.fill")
      } description: {
        Text(.app(.documentsNoPermissionsDescription))
      }
      .padding(.top, 40)
    }
  }
}

// - MARK: Previews

#Preview("NoDocumentsView") {
  NoDocumentsView(filtering: true)
}
