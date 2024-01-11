import CoreTransferable
import Foundation
import OSLog
import SwiftUI

private class LogRecords: Transferable, ObservableObject {
    var logs: String

    init(logs: String) {
        self.logs = logs
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .text, exporting: { record in
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("logs.txt")

            let data = record.logs.data(using: .utf8)!
            try data.write(to: temp, options: .atomic)

            return SentTransferredFile(temp)
        })
    }
}

struct LogRecordDownloadButton: View {
    enum LogState {
        case none
        case loading
        case loaded(logs: String)
        case error(error: Error)
    }

    @State private var state = LogState.none

    private func load() {
        state = .loading
        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let position = store.position(timeIntervalSinceLatestBoot: 1)
            state = try .loaded(logs: store
                .getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == Bundle.main.bundleIdentifier! }
                .map { "[\($0.date.formatted())] [\($0.category)] \($0.composedMessage)" }
                .joined(separator: "\n"))
            Haptics.shared.notification(.success)
        } catch {
            Logger.shared.warning("\(error.localizedDescription, privacy: .public)")
            state = .error(error: error)
            Haptics.shared.notification(.error)
        }
    }

    var body: some View {
        switch state {
        case .none:
            Button {
                Logger.shared.notice("Requesting log export")
                DispatchQueue.global().async {
                    load()
                }
            } label: {
                Label(String(localized: .localizable.logsExport), systemImage: "text.word.spacing")
                    .accentColor(.primary)
            }

        case .loading:
            VStack(alignment: .center) {
                HStack {
                    ProgressView()
                        .padding(.trailing)
                    Text(.localizable.logsExportLoading)
                }
            }

        case let .loaded(logs):
            ShareLink(item: LogRecords(logs: logs), preview: SharePreview("Logs")) {
                Label(String(localized: .localizable.logsExportReady), systemImage: "checkmark.circle.fill")
                    .accentColor(.primary)
            }

        case let .error(error):
            Label(error.localizedDescription, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }
}
