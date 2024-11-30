import CoreTransferable
import Foundation
import OSLog
import SwiftUI

@MainActor
private class LogRecordViewModel: ObservableObject {
    @Published private(set) var state = LogRecordExportButton.LogState.none
    let change: ((LogRecordExportButton.LogState) -> Void)?

    init(change: ((LogRecordExportButton.LogState) -> Void)? = nil) {
        self.change = change
    }

    func load() {
        state = .loading
        change?(state)
        Task.detached {
            do {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let position = store.position(timeIntervalSinceLatestBoot: 1)
                let logs = try store
                    .getEntries(at: position)
                    .compactMap { $0 as? OSLogEntryLog }
                    .filter { $0.subsystem == Bundle.main.bundleIdentifier! }
                    .map { "[\($0.date.formatted())] [\($0.category)] \($0.composedMessage)" }
                    .joined(separator: "\n")

                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("logs.txt")
                let data = logs.data(using: .utf8)!
                try data.write(to: temp, options: .atomic)

                let state: LogRecordExportButton.LogState = .loaded(logs: temp)

                await MainActor.run {
                    self.change?(state)
                    self.state = state
                    Haptics.shared.notification(.success)
                }
            } catch {
                Logger.shared.warning("\(error.localizedDescription, privacy: .public)")
                await MainActor.run {
                    self.state = .error(error: error)
                    self.change?(self.state)
                    Haptics.shared.notification(.error)
                }
            }
        }
    }
}

struct LogRecordExportButton: View {
    enum LogState {
        case none
        case loading
        case loaded(logs: URL)
        case error(error: any Error)
    }

    @ObservedObject private var viewModel: LogRecordViewModel

    let content: (LogState, @escaping () -> Void) -> AnyView

    init(@ViewBuilder content: @escaping (LogState, @escaping () -> Void) -> some View, change: ((LogState) -> Void)? = nil) {
        self.content = { state, export in
            AnyView(content(state, export))
        }
        viewModel = LogRecordViewModel(change: change)
    }

    init(change: ((LogState) -> Void)? = nil) {
        content = { state, export in
            AnyView(Self.defaultContent(state: state, export: export))
        }
        viewModel = LogRecordViewModel(change: change)
    }

    @ViewBuilder
    static func loadingView() -> some View {
        Label(String(localized: .localizable(.logsExportLoading)), systemImage: "ellipsis")
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
    }

    @ViewBuilder
    private static func defaultContent(state: LogState, export: @escaping () -> Void) -> some View {
        switch state {
        case .none:
            Button {
                export()
            } label: {
                Label {
                    Text(.localizable(.logsExport))
                        .accentColor(.primary)
                } icon: {
                    Image(systemName: "text.word.spacing")
                }
            }

        case .loading:
            loadingView()

        case let .loaded(logs):
            ShareLink(item: logs, preview: SharePreview("Logs")) {
                Label(String(localized: .localizable(.logsExportReady)), systemImage: "checkmark.circle.fill")
                    .accentColor(.primary)
            }

        case let .error(error):
            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func export() {
        Logger.shared.notice("Requesting log export")
        viewModel.load()
    }

    var body: some View {
        content(viewModel.state, export)
    }
}
