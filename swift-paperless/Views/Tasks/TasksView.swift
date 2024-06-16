//
//  TasksView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.2024.
//

import os
import SwiftUI

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
            "x.circle"
        case .RETRY:
            "clock.arrow.circlepath"
        case .REVOKED:
            "clock.badge.xmark"
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
        }

        return Label(
            "\(self)".capitalized,
            systemImage: image
        )
        .foregroundColor(color)
    }

    var name: String {
        let res: LocalizedStringResource = switch self {
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
                            .foregroundStyle(.gray)
                        Text(String(task.id))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }

                    Divider()

                    if let created = task.dateCreated {
                        HStack {
                            Text(.tasks(.createdLabel))
                                .foregroundStyle(.gray)
                            Spacer()
                            Text("\(fmt.string(from: created))")
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        Divider()
                    }

                    HStack {
                        Text(.tasks(.status))
                            .foregroundStyle(.gray)
                        Spacer()
                        task.status.label
                            .labelStyle(.iconOnly)
                        Text(task.status.name)
                    }

                    if let result = task.result {
                        Divider()
                        VStack(alignment: .leading) {
                            Text(.tasks(.result))
                                .foregroundStyle(.gray)
                            Text(result)
                                .italic()
                        }
                    }
                }
                .padding()
                .background(Color.systemBackground)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .imageShadow, radius: 10)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(.gray, lineWidth: 0.33))
                .padding()

                if let document {
                    switch document {
                    case let .document(document):
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

                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(.gray, lineWidth: 0.33))
                        }
                        .padding()

                    case let .missing(id):
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

        .task {
            guard let id = task.relatedDocument, let id = UInt(id) else {
                Logger.shared.error("Invalid task id: \(task.relatedDocument ?? "nil", privacy: .public)")
                return
            }
            do {
                if let document = try await store.document(id: id) {
                    withAnimation {
                        self.document = .document(document)
                    }
                } else {
                    withAnimation {
                        document = .missing(id)
                    }
                }
            } catch {
                Logger.shared.error("Unable to get document for related document ID \(id, privacy: .public): \(error)")
            }
        }
    }
}

struct TasksView: View {
    @State var navPath: NavigationPath

    @EnvironmentObject private var store: DocumentStore

    init(navPath: NavigationPath = NavigationPath()) {
        _navPath = State(initialValue: navPath)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            TaskList(tasks: store.tasks, navPath: $navPath)

                .navigationTitle(String(localized: .tasks(.title)))
                .navigationBarTitleDisplayMode(.inline)
                .environmentObject(store)
                .navigationDestination(for: NavigationState.self) { nav in
                    switch nav {
                    case let .detail(document):
                        DocumentDetailView(store: store, document: document, navPath: $navPath)
                    case let .task(task):
                        TaskDetailView(task: task)
                    default:
                        Text("Empty")
                    }
                }
                .animation(.default, value: store.tasks)
        }

        .task {
            store.startTaskPolling()
        }
    }
}

private struct TaskList: View {
    let tasks: [PaperlessTask]

    @Binding var navPath: NavigationPath

    @State private var errorTask: PaperlessTask? = nil

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

    var body: some View {
        Group {
            if !tasks.isEmpty {
                List(tasks, selection: $selection) { task in
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
                                Task {
                                    do {
                                        try await store.acknowledge(tasks: [task.id])
                                    } catch {
                                        Logger.shared.error("Error acknowledging task \(task.id): \(error)")
                                        errorController.push(error: error)
                                    }
                                }
                            } label: {
                                Label(localized: .tasks(.acknowledge), systemImage: "checkmark")
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(String(localized: .tasks(.noTasks)), systemImage: "list.bullet.circle")
            }
        }

        .refreshable {
            store.startTaskPolling()
        }

        .animation(.default, value: editMode)
        .animation(.default, value: store.tasks)

        .environment(\.editMode, $editMode)

        .alert(unwrapping: $errorTask,
               title: { task in Text(.tasks(.missingDocument(String(task.id)))) },
               actions: { _ in })

        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if editMode == .inactive {
                    Button(String(localized: .localizable(.back))) {
                        dismiss()
                    }
                } else {
                    if selection.isEmpty {
                        Button(String(localized: .tasks(.acknowledgeAll)), role: .destructive) {
                            Task {
                                do {
                                    try await store.acknowledge(tasks: store.tasks.map(\.id))
                                    editMode = .inactive
                                } catch {
                                    Logger.shared.error("Error dismissing \(store.tasks.count) tasks: \(error)")
                                    errorController.push(error: error)
                                }
                            }
                        }
                    } else {
                        Button(String(localized: .tasks(.acknowledgeN(UInt(selection.count)))), role: .destructive) {
                            Task {
                                do {
                                    try await store.acknowledge(tasks: Array(selection))
                                } catch {
                                    Logger.shared.error("Error dismissing \(selection.count) tasks: \(error)")
                                    errorController.push(error: error)
                                }
                            }
                        }
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .inactive {
                    Button(String(localized: .localizable(.select))) {
                        editMode = .active
                    }
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
        dateCreated: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
        dateDone: Calendar.current.date(from: DateComponents(year: 2023, month: 12, day: 4, hour: 9, minute: 10, second: 24))!,
        type: .file,
        status: .SUCCESS,
        result: "Success. New document id 2232 created",
        acknowledged: false,
        relatedDocument: "22"
    )

    PreviewHelperView {
        NavigationStack {
            TaskDetailView(task: task)
        }
    }
}
