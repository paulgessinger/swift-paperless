//
//  TasksView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.2024.
//

import os
import SwiftUI

extension TaskStatus {
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
}

struct TaskDetailView: View {
    let task: PaperlessTask

    @EnvironmentObject private var store: DocumentStore
    @State private var document: Document? = nil

    private var title: String {
        String(localized: .tasks.task(String(task.id)))
    }

    private var fmt: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }

    var body: some View {
        Form {
            VStack(alignment: .leading) {
                Text(.tasks.filenameLabel)
                    .foregroundStyle(.gray)
                Text(task.taskFileName ?? String(localized: .tasks.unknownFileName))
                    .bold()
            }

            HStack {
                Text(.tasks.idLabel)
                    .foregroundStyle(.gray)
                Text(String(task.id))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if let created = task.dateCreated {
                HStack {
                    Text(.tasks.createdLabel)
                        .foregroundStyle(.gray)
                    Spacer()
                    Text("\(fmt.string(from: created))")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            HStack {
                Text(.tasks.status)
                    .foregroundStyle(.gray)
                Spacer()
                task.status.label
                    .labelStyle(.iconOnly)
                Text("\(task.status)".capitalized)
            }

            if let result = task.result {
                VStack(alignment: .leading) {
                    Text(.tasks.result)
                        .foregroundStyle(.gray)
                    Text(result)
                        .italic()
                }
            }

            if let document {
                Section(String(localized: .localizable.document)) {
                    NavigationLink(value: NavigationState.detail(document: document)) {
                        DocumentCell(document: document)
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
                let document = try await store.document(id: id)
                withAnimation {
                    self.document = document
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
    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [PaperlessTask] = []

    init(navPath: NavigationPath = NavigationPath()) {
        _navPath = State(initialValue: navPath)
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            TaskList(tasks: tasks, navPath: $navPath)

                .navigationTitle(String(localized: .tasks.title))
                .navigationBarTitleDisplayMode(.inline)
                .environmentObject(store)
                .navigationDestination(for: NavigationState.self) { nav in
                    switch nav {
                    case let .detail(document):
                        DocumentDetailView(document: document, navPath: $navPath)
                    case let .task(task):
                        TaskDetailView(task: task)
                    default:
                        Text("Empty")
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: .localizable.done)) {
                            dismiss()
                        }
                    }
                }
        }

        .task {
            do {
                let tasks = try await store.repository.tasks()
                withAnimation {
                    self.tasks = tasks
                }
            } catch {
                Logger.shared.error("Error getting task sequence")
            }
        }
    }
}

private struct TaskList: View {
    let tasks: [PaperlessTask]

    @Binding var navPath: NavigationPath

    @State private var errorTask: PaperlessTask? = nil

    @EnvironmentObject private var store: DocumentStore

    private var fmt: DateFormatter {
        let fmt = DateFormatter()
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        return fmt
    }

    var body: some View {
        List {
            ForEach(tasks, id: \.id) { task in
                NavigationLink(value: NavigationState.task(task)) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text(String("Task #\(task.id)"))
                            if let created = task.dateCreated {
                                Text("\(fmt.string(from: created))")
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                        .foregroundColor(.gray)

                        let name = task.taskFileName ?? String(localized: .tasks.unknownFileName)
                        HStack(alignment: .top) {
                            task.status.label
                                .labelStyle(.iconOnly)
                            Text("\(name)")
                        }
                        .bold()
                        .font(.body)

//                        if let result = task.result {
//                            Text(result)
//                                .italic()
//                        }
                    }
                    //                .overlay {
                    //                    if let id = task.relatedDocument, let id = UInt(id) {
                    //                        Button {
                    //                            Task {
                    //                                if let document = try await store.document(id: id) {
                    //                                    navPath.append(NavigationState.detail(document: document))
                    //                                }
                    //                                else {
                    //                                    errorTask = task
                    //                                }
                    //                            }
                    //                        } label: {
                    //                            NavigationLink(destination: EmptyView(), label: {EmptyView()})
                    //                        }
                    //                    }
                    //                }
                }
            }
        }
        .alert(unwrapping: $errorTask,
               title: { task in Text(.tasks.missingDocument(String(task.id))) },
               actions: { _ in })
    }
}

#Preview("TaskList") {
    @StateObject var store = DocumentStore(repository: PreviewRepository())
    @State var navPath = NavigationPath()

    return TasksView()
        .environmentObject(store)
}

#Preview("Task") {
    @StateObject var store = DocumentStore(repository: PreviewRepository())

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

    return NavigationStack {
        TaskDetailView(task: task)
    }
    .environmentObject(store)
}
