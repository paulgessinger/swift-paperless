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
            Label(localized: .tasks.title, systemImage: "chart.bar.doc.horizontal")
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

            } label: {}
        }

        .onChange(of: store.tasks) { _ in
            withAnimation {
                number = store.activeTasks.count
            }
        }
    }
}
