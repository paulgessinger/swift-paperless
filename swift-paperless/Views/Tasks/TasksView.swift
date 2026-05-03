//
//  TasksView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.2024.
//

import DataModel
import Networking
import Nuke
import SwiftUI
import os

extension TaskStatus {
  var icon: String {
    switch self {
    case .PENDING:
      "clock"
    case .STARTED:
      "clock.badge.checkmark"
    case .SUCCESS:
      "checkmark.circle"
    case .FAILURE:
      "xmark.circle"
    case .RETRY:
      "clock.arrow.circlepath"
    case .REVOKED:
      "clock.badge.xmark"
    case .UNKNOWN:
      "questionmark.circle"
    }
  }

  var label: some View {
    let image: String
    let color: Color
    switch self {
    case .PENDING:
      image = "clock"
      color = .primary
    case .STARTED:
      image = "clock.badge.checkmark"
      color = .primary
    case .SUCCESS:
      image = "checkmark.circle"
      color = .green
    case .FAILURE:
      image = "x.circle"
      color = .red
    case .RETRY:
      image = "clock.arrow.circlepath"
      color = .yellow
    case .REVOKED:
      image = "clock.badge.xmark"
      color = .yellow
    case .UNKNOWN:
      image = "questionmark.circle"
      color = .secondary
    }

    return Label(
      "\(self)".capitalized,
      systemImage: image
    )
    .foregroundColor(color)
  }

  var name: String {
    let res: LocalizedStringResource =
      switch self {
      case .PENDING:
        .tasks(.statusPending)
      case .STARTED:
        .tasks(.statusStarted)
      case .SUCCESS:
        .tasks(.statusSuccess)
      case .FAILURE:
        .tasks(.statusFailure)
      case .RETRY:
        .tasks(.statusRetry)
      case .REVOKED:
        .tasks(.statusRevoked)
      case .UNKNOWN:
        .tasks(.statusUnknown)
      }

    return String(localized: res)
  }
}

struct TaskDetailView: View {
  let task: PaperlessTask

  @EnvironmentObject private var store: DocumentStore

  private enum DocumentResult {
    case document(_: Document)
    case missing(_: UInt)
  }

  @State private var document: DocumentResult?

  private var title: String {
    String(localized: .tasks(.task(String(task.id))))
  }

  private var fmt: DateFormatter {
    let fmt = DateFormatter()
    fmt.dateStyle = .short
    fmt.timeStyle = .short
    return fmt
  }

  var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading) {
        VStack(alignment: .leading) {
          Text(task.taskFileName ?? String(localized: .tasks(.unknownFileName)))
            .font(.headline)

          Divider()

          HStack {
            Text(.tasks(.idLabel))
              .foregroundStyle(.secondary)
            Text(String(task.id))
              .frame(maxWidth: .infinity, alignment: .trailing)
          }

          Divider()

          if let created = task.dateCreated {
            HStack {
              Text(.tasks(.createdLabel))
                .foregroundStyle(.secondary)
              Spacer()
              Text("\(fmt.string(from: created))")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Divider()
          }

          HStack {
            Text(.tasks(.status))
              .foregroundStyle(.secondary)
            Spacer()
            task.status.label
              .labelStyle(.iconOnly)
            Text(task.status.name)
          }

          if let result = task.result {
            Divider()
            VStack(alignment: .leading) {
              Text(.tasks(.result))
                .foregroundStyle(.secondary)
              Text(result)
                .italic()
            }
          }
        }
        .padding()
        //                .background(Color.systemBackground)
        .clipShape(RoundedRectangle(cornerRadius: 25, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 25, style: .continuous)
            .stroke(.tertiary)
        )
        .padding()

        if let document {
          switch document {
          case .document(let document):
            VStack {
              Text(.tasks(.relatedDocument))
                .font(.headline)
                .padding(.top, 30)
                .frame(maxWidth: .infinity, alignment: .center)

              HStack {
                DocumentCell(document: document, store: store)
                Label(localized: .localizable(.more), systemImage: "chevron.right")
                  .labelStyle(.iconOnly)
                  .foregroundColor(.gray)
                  .font(.callout)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.horizontal)
              .padding(.vertical, 15)
              .overlay {
                NavigationLink(value: NavigationState.detail(document: document)) {
                  Color.clear
                }
              }

              .overlay(
                RoundedRectangle(cornerRadius: 25, style: .continuous)
                  .stroke(.tertiary))
            }
            .padding()

          case .missing(let id):
            Text(.tasks(.missingDocument(String(id))))
              .padding()
              .italic()
              .multilineTextAlignment(.center)
          }
        }
      }
    }
    .navigationTitle(title)
    .navigationBarTitleDisplayMode(.inline)
    .scrollBounceBehavior(.basedOnSize)

    .task {
      guard let id = task.relatedDocument, let id = UInt(id) else {
        Logger.shared.error("Invalid task id: \(task.relatedDocument ?? "nil", privacy: .public)")
        return
      }
      do {
        if let document = try await store.document(id: id) {
          store.preloadThumbnail(for: document)
          withAnimation {
            self.document = .document(document)
          }
        } else {
          withAnimation {
            document = .missing(id)
          }
        }
      } catch {
        Logger.shared.error(
          "Unable to get document for related document ID \(id, privacy: .public): \(error)")
        withAnimation {
          document = .missing(id)
        }
      }
    }
  }
}

@MainActor
@Observable
final class TaskListViewModel {
  var tasks: [PaperlessTask] = []
  var ready = false

  private weak var store: DocumentStore?
  private var source: (any TaskSource)?
  private var exhausted = false

  private let initialBatchSize: UInt = 100
  private let batchSize: UInt = 100
  private let fetchMargin = 10

  init(store: DocumentStore) {
    self.store = store
  }

  func load() async {
    guard let store, tasks.isEmpty else { return }
    do {
      let source = try store.repository.tasks()
      self.source = source
      tasks = try await source.fetch(limit: initialBatchSize)
      exhausted = await !source.hasMore()
      ready = true
    } catch {
      Logger.shared.error("TaskList failed to load: \(error)")
      ready = true
    }
  }

  func refresh() async {
    source = nil
    exhausted = false
    tasks = []
    ready = false
    await load()
  }

  func fetchMoreIfNeeded(currentIndex: Int) async {
    guard !exhausted, let source else { return }
    guard currentIndex >= tasks.count - fetchMargin else { return }

    do {
      let batch = try await source.fetch(limit: batchSize)
      if batch.isEmpty {
        exhausted = true
        return
      }
      tasks.append(contentsOf: batch)
      exhausted = await !source.hasMore()
    } catch {
      Logger.shared.error("TaskList failed to load more: \(error)")
    }
  }

  func remove(ids: Set<UInt>) {
    tasks.removeAll { ids.contains($0.id) }
  }
}

struct TasksView: View {
  @State var navPath: [NavigationState]

  @EnvironmentObject private var store: DocumentStore

  init(navPath: [NavigationState] = []) {
    _navPath = State(initialValue: navPath)
  }

  var body: some View {
    NavigationStack(path: $navPath) {
      TaskList(navPath: $navPath)

        .navigationTitle(String(localized: .tasks(.title)))
        .navigationBarTitleDisplayMode(.inline)
        .environmentObject(store)
        .navigationDestination(for: NavigationState.self) { nav in
          switch nav {
          case .detail(let document):
            DocumentDetailView(store: store, document: document, navPath: $navPath)
          case .task(let task):
            TaskDetailView(task: task)
          default:
            Text("Empty")
          }
        }
    }

    .task {
      store.startTaskPolling()
    }
  }
}

private struct TaskList: View {
  @Binding var navPath: [NavigationState]

  @State private var errorTask: PaperlessTask? = nil
  @State private var viewModel: TaskListViewModel?

  @EnvironmentObject private var store: DocumentStore
  @EnvironmentObject private var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss
  @State private var selection = Set<UInt>()
  @State var editMode: EditMode = .inactive

  private var fmt: DateFormatter {
    let fmt = DateFormatter()
    fmt.dateStyle = .short
    fmt.timeStyle = .short
    return fmt
  }

  private func acknowledge(ids: [UInt]) async {
    do {
      try await store.acknowledge(tasks: ids)
      viewModel?.remove(ids: Set(ids))
    } catch {
      Logger.shared.error("Error acknowledging \(ids.count) task(s): \(error)")
      errorController.push(error: error)
    }
  }

  private func mainList(viewModel: TaskListViewModel) -> some View {
    List(selection: $selection) {
      ForEach(Array(zip(viewModel.tasks.indices, viewModel.tasks)), id: \.1.id) { idx, task in
        NavigationLink(value: NavigationState.task(task)) {
          VStack(alignment: .leading) {
            HStack {
              Text(String(localized: .tasks(.task(String(task.id)))))
              if let created = task.dateCreated {
                Text("\(fmt.string(from: created))")
                  .frame(maxWidth: .infinity, alignment: .trailing)
              }
            }
            .foregroundColor(.gray)

            let name = task.taskFileName ?? String(localized: .tasks(.unknownFileName))
            HStack(alignment: .top) {
              task.status.label
                .labelStyle(.iconOnly)
              Text("\(name)")
            }
            .bold()
            .font(.body)
          }

          .swipeActions(edge: .trailing) {
            Button {
              Task { await acknowledge(ids: [task.id]) }
            } label: {
              Label(localized: .tasks(.acknowledge), systemImage: "checkmark")
            }
          }
        }
        .task {
          await viewModel.fetchMoreIfNeeded(currentIndex: idx)
        }
      }
    }
  }

  private struct NoPermissionsView: View {
    var body: some View {
      ContentUnavailableView(
        String(localized: .permissions(.noViewPermissionsDisplayTitle)),
        systemImage: "lock.fill",
        description: Text(.permissions(.noViewPermissionsTasks)))
    }
  }

  private struct NoElementsView: View {
    var body: some View {
      ContentUnavailableView(
        String(localized: .localizable(.noElementsFound)),
        systemImage: "list.bullet.circle.fill",
        description: Text(.tasks(.title)))
    }
  }

  var body: some View {
    Group {
      if !store.permissions.test(.view, for: .paperlessTask) {
        Form {
          NoPermissionsView()
        }
      } else if let viewModel, !viewModel.tasks.isEmpty {
        mainList(viewModel: viewModel)
      } else {
        Form {
          NoElementsView()
            .padding(.top, 50)
        }
      }
    }

    .task {
      if viewModel == nil {
        viewModel = TaskListViewModel(store: store)
      }
      await viewModel?.load()
    }

    .refreshable {
      store.startTaskPolling()
      await viewModel?.refresh()
    }

    .animation(.default, value: editMode)
    .animation(.default, value: viewModel?.tasks ?? [])

    .environment(\.editMode, $editMode)

    .alert(
      unwrapping: $errorTask,
      title: { task in Text(.tasks(.missingDocument(String(task.id)))) },
      actions: { _ in }
    )

    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        if editMode == .inactive {
          CancelIconButton()
        } else {
          if selection.isEmpty {
            // Acknowledges only the loaded subset; remaining unacknowledged
            // tasks past the scroll-load horizon are left for a follow-up pass.
            let loadedIds = viewModel?.tasks.map(\.id) ?? []
            Button(String(localized: .tasks(.acknowledgeAll)), role: .destructive) {
              Task {
                await acknowledge(ids: loadedIds)
                editMode = .inactive
              }
            }
            .disabled(loadedIds.isEmpty)
          } else {
            Button(
              String(localized: .tasks(.acknowledgeN(UInt(selection.count)))), role: .destructive
            ) {
              Task { await acknowledge(ids: Array(selection)) }
            }
          }
        }
      }

      ToolbarItem(placement: .topBarTrailing) {
        if editMode == .inactive {
          Button(String(localized: .localizable(.select))) {
            editMode = .active
          }
          .disabled(viewModel?.tasks.isEmpty ?? true)
        } else {
          Button(String(localized: .localizable(.done))) {
            editMode = .inactive
          }
        }
      }
    }
  }
}

// MARK: - Previews

private struct PreviewHelperView<Content: View>: View {
  @StateObject private var store = DocumentStore(repository: PreviewRepository())

  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .environmentObject(store)
  }
}

#Preview("TaskList") {
  PreviewHelperView {
    TasksView()
  }
}

#Preview("Task") {
  let task = PaperlessTask(
    id: 2748,
    taskId: UUID(uuidString: "ef16d8fb-c495-4850-92b8-73a64109674e")!,
    taskFileName: "2021-05-04--Letter_Vorläufiger Bescheid Promotion__DOCT.pdf",
    dateCreated: Calendar.current.date(
      from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
    dateDone: Calendar.current.date(
      from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
    type: "file",
    status: .SUCCESS,
    result: "Success. New document id 2232 created",
    acknowledged: false,
    relatedDocument: "22"
  )

  return PreviewHelperView {
    NavigationStack {
      TaskDetailView(task: task)
    }
  }
}
