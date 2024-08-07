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
    var more: String {
        if store.tasks.count > Self.numTasks {
            return String(localized: .tasks(.tasksMenuMoreLabel(UInt(store.tasks.count - Self.numTasks))))
        } else {
            return String(localized: .tasks(.tasksMenuAllLabel))
        }
    }

    var body: some View {
        Group {
            Label(localized: .tasks(.title),
                  systemImage: "checklist")
                .tint(.accent)
        }
        .overlay {
            Menu {
                ForEach(store.tasks.prefix(Self.numTasks)) { task in
                    let filename = task.taskFileName ?? String(localized: .tasks(.unknownFileName))
                    Button {
                        navState = .task(task)
                    } label: {
                        Label(filename, systemImage: task.status.icon)
                    }
                }

                Divider()

                Button(more) {
                    navState = .tasks
                }

            } label: {}
        }

        .onChange(of: store.tasks) {
            withAnimation {
                number = store.activeTasks.count
            }
        }
    }
}
