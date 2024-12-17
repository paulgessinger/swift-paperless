import CoreTransferable
import Foundation
import Observation
import OSLog
import SwiftUI

@MainActor
@Observable
private class LogRecordViewModel {
    private(set) var state = LogRecordExportButton.LogState.none

    @ObservationIgnored
    let change: ((LogRecordExportButton.LogState) -> Void)?

    init(change: ((LogRecordExportButton.LogState) -> Void)? = nil) {
        self.change = change
    }

    func load() async {
        state = .loading
        change?(state)

        let task = Task.detached {
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

            return temp
        }

        do {
            let result = try await task.result.get()
            state = .loaded(logs: result)
            change?(state)
            Haptics.shared.notification(.success)
        } catch {
            Logger.shared.warning("\(error.localizedDescription, privacy: .public)")
            state = .error(error: error)
            Haptics.shared.notification(.error)
        }
    }
}

private struct ActivityViewController: UIViewControllerRepresentable {
    var activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context _: UIViewControllerRepresentableContext<ActivityViewController>) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return controller
    }

    func updateUIViewController(_: UIActivityViewController, context _: UIViewControllerRepresentableContext<ActivityViewController>) {}
}

struct LogRecordExportButton: View {
    enum LogState {
        case none
        case loading
        case loaded(logs: URL)
        case error(error: any Error)
    }

    @State private var viewModel: LogRecordViewModel

    let content: ((LogState, @escaping () -> Void) -> AnyView)?

    init(@ViewBuilder content: @escaping (LogState, @escaping () -> Void) -> some View, change: ((LogState) -> Void)? = nil) {
        self.content = { state, export in
            AnyView(content(state, export))
        }
        _viewModel = State(initialValue: LogRecordViewModel(change: change))
    }

    init(change: ((LogState) -> Void)? = nil) {
        content = nil
        _viewModel = State(initialValue: LogRecordViewModel(change: change))
    }

    @ViewBuilder
    static func loadingView() -> some View {
        Label(String(localized: .localizable(.logsExportLoading)), systemImage: "ellipsis")
            .symbolEffect(.variableColor.iterative.dimInactiveLayers.nonReversing)
    }

    @ViewBuilder
    private var defaultContent: some View {
        VStack {
            switch viewModel.state {
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
                Self.loadingView()

            case let .loaded(logs):
                ShareLink(item: logs, preview: SharePreview("Logs")) {
                    Label {
                        Text(.localizable(.logsExportReady))
                            .accentColor(.primary)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                }

            case let .error(error):
                Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    private func export() {
        Logger.shared.notice("Requesting log export")
        Task {
            await viewModel.load()
        }
    }

    var body: some View {
        if let content {
            content(viewModel.state, export)
        } else {
            defaultContent
        }
    }
}
