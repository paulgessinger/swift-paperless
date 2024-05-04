//
//  TaskActivityToolbar.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.05.2024.
//

import os
import SwiftUI

struct TaskActivityToolbar: View {
    @EnvironmentObject var store: DocumentStore

    @State private var number: Int?

    var body: some View {
        Rectangle()
            .fill(.clear)
            .overlay {
                if let number, number > 0 {
                    Menu {
                        ForEach(store.activeTasks.filter { $0.status == .STARTED }, id: \.id) { task in
                            let name = (task.taskFileName ?? task.taskName) ?? "unknown task"
                            Text(.localizable.tasksProcessing(name))
                        }
                        let queued = store.activeTasks.filter { $0.status != .STARTED }.count
                        if queued > 0 {
                            Divider()
                            Text(.localizable.tasksPending(UInt(queued)))
                        }
                    } label: {
                        TaskActivityView(text: "\(number)")
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal)

            .task {
                repeat {
                    Logger.shared.trace("Loading tasks")

                    // @TODO: Improve backend API to allow fetching only active:
//                https://github.com/paperless-ngx/paperless-ngx/blob/83f9f2d3870556a8f55167cbc89375fc967965a8/src/documents/views.py#L1072
                    await store.fetchTasks()

                    try? await Task.sleep(for: .seconds(10))
                } while !Task.isCancelled
            }

            .onChange(of: store.activeTasks) { _ in
                withAnimation {
                    number = store.activeTasks.count
                }
            }
    }
}
