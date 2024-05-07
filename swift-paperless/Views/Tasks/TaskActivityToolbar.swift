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
                ForEach(store.tasks.prefix(Self.numTasks)) { task in
                    let filename = task.taskFileName ?? String(localized: .tasks.unknownFileName)
                    Button {
                        navState = .task(task)
                    } label: {
                        Label(filename, systemImage: task.status.icon)
                    }
                }

                Divider()

                let more = String(localized: store.tasks.count > Self.numTasks ? .tasks.tasksMenuMoreLabel(UInt(store.tasks.count - Self.numTasks)) : .tasks.tasksMenuAllLabel)
                Button(more) {
                    navState = .tasks
                }

            } label: {
                TaskActivityView(text: "\(number)")
            }
        }
        .transition(.opacity)

        .onChange(of: store.tasks) { _ in
            withAnimation {
                number = store.activeTasks.count
            }
        }
    }
}
