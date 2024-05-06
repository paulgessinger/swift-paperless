//
//  TaskActivityToolbar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.2024.
//

import os
import SwiftUI

struct TaskActivityToolbar: View {
    @Binding var navState: NavigationState?

    @EnvironmentObject var store: DocumentStore

    @State private var number: Int = 0
    @State private var tasks: [PaperlessTask] = []

    static let numTasks = 5

    var body: some View {
        Group {
            if store.activeTasks.count > 0 {
                TaskActivityView(text: "\(number)")
            } else {
                Label(localized: .tasks.title, systemImage: "list.bullet")
                    .labelStyle(.iconOnly)
            }
        }
        .overlay {
            Menu {
                ForEach(tasks.prefix(Self.numTasks)) { task in
                    let filename = task.taskFileName ?? String(localized: .tasks.unknownFileName)
                    Button {
                        navState = .task(task)
                    } label: {
                        Label(filename, systemImage: task.status.icon)
                    }
                }

                Divider()

                let more = String(localized: tasks.count > Self.numTasks ? .tasks.tasksMenuMoreLabel(UInt(tasks.count - Self.numTasks)) : .tasks.tasksMenuAllLabel)
                Button(more) {
                    navState = .tasks
                }

//                ForEach(store.activeTasks.filter { $0.status == .STARTED }, id: \.id) { task in
//                    let name = (task.taskFileName ?? task.taskName) ?? "unknown task"
//                    Text(.localizable.tasksProcessing(name))
//                }
//                let queued = store.activeTasks.filter { $0.status != .STARTED }.count
//                if queued > 0 {
//                    Divider()
//                    Text(.localizable.tasksPending(UInt(queued)))
//                }
            } label: {
                TaskActivityView(text: "\(number)")
            }
        }
        .transition(.opacity)

        .task {
            if let tasks = try? await store.repository.tasks() {
                self.tasks = tasks
//                        .sorted(by: { $0.dateCreated? < $1.dateCreated }) // probably unnecessary
//                    .prefix(Self.numTasks))
            }

//                repeat {
//                    Logger.shared.trace("Loading tasks")
//
//                    // @TODO: Improve backend API to allow fetching only active:
            ////                https://github.com/paperless-ngx/paperless-ngx/blob/83f9f2d3870556a8f55167cbc89375fc967965a8/src/documents/views.py#L1072
//                    await store.fetchTasks()
//
//                    try? await Task.sleep(for: .seconds(10))
//                } while !Task.isCancelled
        }

        .onChange(of: store.activeTasks) { _ in
            withAnimation {
                number = store.activeTasks.count
            }
        }
    }
}
