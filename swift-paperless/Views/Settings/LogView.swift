//
//  LogView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 06.09.25.
//

import Common
import OSLog
import SwiftUI

private extension OSLogEntryLog.Level {
    var color: Color {
        switch self {
        case .debug:
            .gray
        case .error, .fault:
            .red
        case .info, .notice, .undefined:
            .primary
        @unknown default:
            .primary
        }
    }

    var description: String {
        switch self {
        case .info:
            "INFO"
        case .notice:
            "NOTICE"
        case .debug:
            "DEBUG"
        case .error:
            "ERROR"
        case .fault:
            "FAULT"
        case .undefined:
            "UNDEFINED"
        @unknown default:
            "UNKNOWN"
        }
    }
}

struct LogView: View {
    private enum LogState: Equatable {
        case loading
        case loaded([Entry], URL?)
        case error(String)
    }

    @State private var state = LogState.loading

    fileprivate init(entries: [Entry]) {
        _state = State(initialValue: .loaded(entries, nil))
    }

    init() {}

    fileprivate struct Entry: Hashable, Equatable {
        let date: Date
        let category: String
        let message: String
        let level: OSLogEntryLog.Level

        var formatted: String {
            "[\(date.formatted())] [\(level.description)] [\(category)] \(message)"
        }
    }

    private struct GenericError: Error {
        let message: String
    }

    private func loadLogs() async {
        if state != .loading {
            return
        }

        let task = Task.detached {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceLatestBoot: 1)
            var entries = try store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == Bundle.main.bundleIdentifier! }
                .map { Entry(date: $0.date, category: $0.category, message: $0.composedMessage, level: $0.level) }

            var file: URL? = nil

            do {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("logs.txt")

                let data = entries
                    .map(\.formatted)
                    .joined(separator: "\n").data(using: .utf8)!
                try data.write(to: temp, options: .atomic)
                file = temp
            } catch {
                let logMsg = "Failed to write logs to temporary file: \(String(describing: error))"
                // Add this to the log manually, so that we can display it
                entries.append(Entry(date: .now, category: "ERROR", message: logMsg, level: .error))

                Logger.shared.error("Failed to write logs to temporary file: \(error, privacy: .public)")
            }

            return (entries, file)
        }

        do {
            let (entries, result) = try await task.result.get()
            if Task.isCancelled {
                return
            }

            if let result {
                Haptics.shared.notification(.success)
                Logger.shared.info("Logs written to \(result.path, privacy: .public)")
            } else {
                Haptics.shared.notification(.warning)
                Logger.shared.warning("No log file created")
            }
            state = .loaded(entries, result)
        } catch {
            Logger.shared.warning("\(error, privacy: .public)")
            state = .error(error.localizedDescription)
        }
    }

    private var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        return formatter
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if case let .loaded(_, file) = state, file == nil {
                    Section {
                        HStack(alignment: .top) {
                            Image(systemName: "info.circle.fill")
                            Text(.localizable(.logsExportNoFile))
                        }
                    }
                }

                if case let .loaded(entries, _) = state, !entries.isEmpty {
                    Section {
                        Button {
                            withAnimation(.spring) {
                                proxy.scrollTo(entries.count - 1, anchor: .bottom)
                            }
                        } label: {
                            Label(.localizable(.scrollToBottom), systemImage: "arrow.down.to.line.alt")
                        }
                    }
                }

                Section {
                    switch state {
                    case .loading:
                        HStack {
                            ProgressView()
                            Text(.localizable(.logsExportLoading))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)

                    case let .loaded(entries, _):
                        ForEach(Array(zip(entries.indices, entries)),
                                id: \.0)
                        { i, entry in

                            VStack(alignment: .leading) {
                                HStack(alignment: .top) {
                                    Text(entry.level.description)
                                        .bold()
                                    Text("[\(entry.category)]")

                                    Spacer()

                                    Text("\(entry.date, formatter: formatter)")
                                }

                                Text(entry.message)
                            }

                            .contextMenu {
                                Button(.localizable(.copyToClipboard)) {
                                    Pasteboard.general.string = entry.formatted
                                }
                            }

                            .foregroundStyle(entry.level.color)
                            .font(.system(size: 14, design: .monospaced))
                            .padding(.horizontal)
                            .padding(.vertical, 5)
                            .listRowInsets(EdgeInsets())

                            .id(i)
                        }

                    case let .error(message):
                        HStack(alignment: .top) {
                            Image(systemName: "xmark.circle.fill")
                            Text(message)
                        }
                        .foregroundStyle(.red)
                    }
                }
            }

            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if case let .loaded(entries, file) = state {
                        Button {
                            let payload = entries.map(\.formatted).joined(separator: "\n")

                            Pasteboard.general.string = payload
                            Haptics.shared.notification(.success)
                        } label: {
                            Label(.localizable(.copyToClipboard), systemImage: "doc.on.doc")
                        }

                        ShareLink(item: file ?? URL(filePath: "")!, preview: SharePreview("Logs")) {
                            Label(.localizable(.share), systemImage: "square.and.arrow.up")
                        }
                        .disabled(file == nil)
                    }
                }
            }

            .task {
                await loadLogs()
                if case let .loaded(entries, _) = state, !entries.isEmpty {
                    do {
                        try await Task.sleep(for: .seconds(0.5))
                        withAnimation(.spring) {
                            proxy.scrollTo(entries.count - 1, anchor: .bottom)
                        }
                    } catch {}
                }
            }

            .animation(.spring, value: state)

            .navigationTitle(.settings(.logs))
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private typealias Entry = LogView.Entry

#Preview {
    NavigationStack {
        LogView(entries: [
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is another test log entry", level: .error),
            Entry(date: .now, category: "test", message: "this is yet another test log entry and it's even much more longer", level: .debug),
            Entry(date: .now, category: "TEST", message: "This is another test log entry", level: .error),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "test", message: "this is yet another test and as soon as it", level: .debug),
            Entry(date: .now, category: "TEST", message: "This is another test log entry", level: .error),

            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
            Entry(date: .now, category: "TEST", message: "This is a test log entry", level: .info),
        ])
    }
}
