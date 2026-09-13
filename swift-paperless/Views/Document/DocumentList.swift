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
    // Deliberately unlocalized: `.redacted(reason: .placeholder)` masks the text
    // and the date, so nothing here reaches the user. A fixed date rather than
    // `.now` because the value is re-derived on every render and no one can see
    // it anyway.
    Document(
      id: id, title: "Loading document title",
      created: Date(timeIntervalSince1970: 0), tags: [])
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
      documents =
        (try? await PreviewRepository().documents(filter: .default).fetch(limit: 10)) ?? []
    }
  }
}

struct DocumentList: View {
  var store: DocumentStore
  var onSelect: (Document) -> Void
  var filterModel: FilterModel
  // iPad split-view: highlights the row matching the selected detail doc.
  // Nil on iPhone (push-based navigation needs no list-side highlight).
  var selectedDocumentID: UInt?

  @State private var documentToDelete: Document?

  @State private var viewModel: DocumentListViewModel

  @EnvironmentObject private var errorController: ErrorController

  private let appSettings = AppSettings.shared

  init(
    store: DocumentStore, onSelect: @escaping (Document) -> Void, filterModel: FilterModel,
    errorController: ErrorController,
    selectedDocumentID: UInt? = nil
  ) {
    self.store = store
    self.onSelect = onSelect
    self.filterModel = filterModel
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
            errorController.push(mutationError: error)
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
      // observation repaints the list in place (a delete is explicitly pruned
      // out of every query_order — no FK cascade does this). Nothing to do here.
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

  private func retry() {
    Task {
      await viewModel.retry()
    }
  }

  /// Names the list that failed: the default list, the saved view by name, or
  /// the current filter. A saved view whose name isn't cached is worded as a
  /// filter rather than guessed at.
  private func failureTitle(incomplete: Bool) -> String {
    if case .savedView(let id) = viewModel.scope, let name = store.savedViews[id]?.name {
      return incomplete
        ? String(localized: .app(.documentListIncompleteSavedView(name)))
        : String(localized: .app(.documentListUnavailableSavedView(name)))
    }
    if viewModel.scope == .allDocuments {
      return incomplete
        ? String(localized: .app(.documentListIncomplete))
        : String(localized: .app(.documentListUnavailable))
    }
    return incomplete
      ? String(localized: .app(.documentListIncompleteFilter))
      : String(localized: .app(.documentListUnavailableFilter))
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
        let state = viewModel.state
        switch state.content {
        case .loading:
          // Still filling (cold cache + a fill in flight, or the server reports
          // a non-empty count): don't flash "No documents" during the fill.
          LoadingDocumentList()
        case .empty:
          NoDocumentsView(filtering: filterModel.filterState.filtering)
            .equatable()
            .refreshable {
              await Task {
                await refresh()
              }.value
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .unavailable:
          // The load failed and nothing is cached: say so rather than claim
          // the query matched no documents.
          DocumentsUnavailableView(
            title: failureTitle(incomplete: false),
            message: viewModel.fillErrorDescription,
            retry: retry
          )
          .refreshable {
            await Task {
              await refresh()
            }.value
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .documents:
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
                      // redacted placeholder. `listRowInsets` matches what
                      // `Cell` sets on the loaded branch — without it a skeleton
                      // keeps List's default insets *on top of* its own padding
                      // and sits visibly narrower than its neighbours, which is
                      // the normal state of a list mid-fill.
                      DocumentCell(document: .skeletonPlaceholder(id: id), store: store)
                        .padding(.horizontal)
                        .padding(.vertical)
                        .redacted(reason: .placeholder)
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
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
            // Pinned below the filter bar: the rows scroll under it, so the
            // notice stays in view however far down the truncated list goes.
            .safeAreaInset(edge: .top, spacing: 0) {
              if state.isIncomplete {
                IncompleteDocumentsBanner(
                  title: failureTitle(incomplete: true),
                  error: viewModel.fillFailure,
                  retry: retry
                )
                .transition(.move(edge: .top).combined(with: .opacity))
              }
            }
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
    .animation(.default, value: viewModel.state)

    .onChange(of: filterModel.filterState) { _, filter in
      Task {
        await viewModel.refresh(filter: filter)
      }
    }

    .onChange(of: viewModel.isFetching) { _, fetching in
      filterModel.isFetching = fetching
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

    .onAppear {
      viewModel.noteAppeared()
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
              errorController.push(mutationError: error)
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

/// The list's load-failure state: shown instead of `NoDocumentsView` when the
/// query couldn't be loaded and nothing is cached, so a failure never reads as
/// "no matching documents".
private struct DocumentsUnavailableView: View {
  var title: String
  var message: String?
  var retry: () -> Void

  var body: some View {
    ScrollView(.vertical) {
      ContentUnavailableView {
        Label(title, systemImage: "exclamationmark.triangle")
      } description: {
        if let message {
          Text(message)
        }
      } actions: {
        Button(String(localized: .app(.documentListRetry)), action: retry)
          .buttonStyle(.bordered)
      }
      .padding(.top, 40)
    }
  }
}

/// Above rows from a truncated cache whose fill failed: the documents shown are
/// not the whole answer.
///
/// Pinned over the list, so it keeps one height whatever the error says: only
/// the error's headline shows, and tapping it opens the full text in the same
/// alert an error toast's details open.
private struct IncompleteDocumentsBanner: View {
  var title: String
  var error: (any DisplayableError)?
  var retry: () -> Void

  @State private var detail: (any DisplayableError)?

  private var summary: some View {
    HStack(spacing: 12) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.subheadline)
          .fontWeight(.semibold)
        if let error {
          HStack(spacing: 4) {
            Text(error.message)
              .lineLimit(1)
            if error.details != nil {
              Image(systemName: "info.circle")
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
    .contentShape(Rectangle())
  }

  var body: some View {
    HStack(spacing: 12) {
      if let error, error.details != nil {
        Button {
          detail = error
        } label: {
          summary
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(.app(.errorAlertTapForDetails)))
      } else {
        summary
      }
      Button(String(localized: .app(.documentListRetry)), action: retry)
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    .padding(12)
    .background(
      Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
    )
    // Rows scroll under the inset, so the tint alone would let them show through.
    .backport.glassEffect(
      .regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous),
      orFill: .regularMaterial)
    // Two separate targets: the details and Retry.
    .accessibilityElement(children: .contain)
    .padding(.horizontal)
    .padding(.vertical, 6)
    .alert(
      unwrapping: $detail,
      title: { Text($0.message) },
      actions: { ErrorAlertActions(for: $0) },
      message: { detail in
        if let details = detail.details {
          Text(details)
        }
      })
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

#Preview("Incomplete list") {
  // The real list over a fill that loses the connection after its first page:
  // a truncated cache plus a failed fill, which is what shows the banner.
  @Previewable @State var store = DocumentStore.preview(PreviewRepository(failDocumentsAfter: 8))
  @Previewable @StateObject var errorController = ErrorController()
  @Previewable @State var filterModel = FilterModel()
  @Previewable @State var connectionManager = ConnectionManager(
    database: try! Database.inMemory())

  // Hosted like `DocumentView.compactBody`, so the banner sits under the filter bar.
  NavigationStack {
    DocumentList(
      store: store, onSelect: { _ in }, filterModel: filterModel,
      errorController: errorController)
      .apply {
        if #available(iOS 26.0, *) {
          $0.scrollEdgeEffectHidden(true, for: .top)
        } else {
          $0
        }
      }
      .safeAreaInset(edge: .top) {
        if #available(iOS 26.0, *) {
          FilterAssembly(filterModel: filterModel)
        } else {
          FilterAssemblyiOS18(filterModel: filterModel)
        }
      }
      .toolbarBackground(.hidden, for: .navigationBar)
      .navigationTitle("Documents")
      .navigationBarTitleDisplayMode(.inline)
  }
  .environment(store)
  .environmentObject(errorController)
  .environment(connectionManager)
  .environment(filterModel)
  .environment(RouteManager())
}
