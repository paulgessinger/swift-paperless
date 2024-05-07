import AsyncAlgorithms
import Foundation
import os
import SwiftUI

protocol DisplayableError: Error {
    var message: String { get }
    var details: String? { get }
    var documentationLink: URL? { get }
}

extension DisplayableError {
    var documentationLink: URL? { nil }
}

struct GenericError: DisplayableError {
    let message: String
    let details: String?

    init(message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }
}

@MainActor
class ErrorController: ObservableObject {
    enum State {
        case none
        case active(error: DisplayableError, duration: Double)
    }

    @Published var state: State = .none

    private static let defaultTitle = String(localized: .localizable.errorDefaultMessage)

    private var channel = AsyncChannel<DisplayableError>()
    private var task: Task<Void, Never>? = nil

    init() {
        task = Task(operation: worker)
    }

    deinit {
        task?.cancel()
        channel.finish()
    }

    @Sendable
    private func worker() async {
        Logger.shared.debug("ErrorController worker started")
        for await error in channel {
            guard !Task.isCancelled else { break }
            Logger.shared.debug("ErrorController worker got error from channel")

            Haptics.shared.notification(.error)
            let duration = 5.0
            withAnimation(.spring(duration: 0.3)) {
                state = State.active(error: error, duration: duration)
            }
            try? await Task.sleep(for: .seconds(0.3 + duration + 0.4))
        }
        Logger.shared.debug("ErrorController worker terminated")
    }

    func push(error: Error, message: String? = nil) {
        if let le = error as? LocalizedError {
            if let message {
                Task {
                    push(error: GenericError(message: message, details: String(describing: error)))
                }
            } else {
                push(error: le)
            }
            return
        }

        if let de = error as? DisplayableError {
            push(error: de)
            return
        }
        push(message: message ?? Self.defaultTitle, details: error.localizedDescription)
    }

    func push(error: Error, message: LocalizedStringResource) {
        push(error: error, message: String(localized: message))
    }

    func push(error: LocalizedError) {
        push(error: GenericError(message: error.errorDescription ?? Self.defaultTitle, details: error.failureReason))
    }

    func push(error: DisplayableError) {
        Task {
            await channel.send(error)
        }
    }

    func push(message: String, details: String? = nil) {
        push(error: GenericError(message: message, details: details))
    }

    func clear(animate: Bool = true) {
        Task {
            await MainActor.run {
                if animate {
                    withAnimation {
                        state = .none
                    }
                } else {
                    state = .none
                }
            }
        }
    }
}

// MARK: Previews

private struct PreviewError: LocalizedError {
    var errorDescription: String? { String(localized: .localizable.errorDefaultMessage) }
}

struct ErrorOverlay_Previews: PreviewProvider {
    struct MyButton: View {
        @EnvironmentObject var errorController: ErrorController

        var body: some View {
            Button(String("Trigger error")) {
                errorController.push(error: PreviewError())
            }
        }
    }

    struct Container: View {
//        @State var error: LocalizedError? = PreviewError()

        @StateObject var errorController = ErrorController()

        var body: some View {
            ScrollView {
                MyButton()
                Rectangle()
                    .frame(height: 300)
            }
//            .overlay(alignment: .bottom) {
//                if let (e, d) = errorController.active {
//                    ErrorView(error: e, duration: d)
//                        .transition(.move(edge: .bottom).combined(with: .opacity))
//                        .zIndex(1)
//                        .id(UUID())
//                }
//            }
            .errorOverlay(errorController: errorController)
            .environmentObject(errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
