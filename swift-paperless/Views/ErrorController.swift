import Foundation
import SwiftUI

struct ErrorDisplay: ViewModifier {
    @ObservedObject var errorController: ErrorController
    @State private var detail: DisplayableError? = nil
    @State private var alertOffset = CGSize.zero

    @State private var dismissTask: Task<Void, Never>? = nil
    @State private var ready = false

    func createAutoDismissTask(duration: Double) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else {
                return
            }
            errorController.clear()
        }
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                switch errorController.state {
                case let .active(error, duration):
                    HStack {
                        Label(error.message,
                              systemImage: "xmark")
                            .labelStyle(.iconOnly)
                            .foregroundColor(.red)
                            .scaleEffect(1.5)

                        VStack(alignment: .leading) {
                            Text(error.message)
                                .bold()
                            if error.details != nil {
                                Text(.localizable.errorAlertTapForDetails)
                                    .font(Font.custom("", size: 14))
                            }
                        }
                        .font(Font.body.leading(.tight))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, error.details == nil ? 10 : 7)

                    .contentShape(Capsule())

                    .background(Capsule()
                        .strokeBorder(.gray, lineWidth: 0.66)
                        .background(
                            Capsule().fill(
                                Material.bar
                            )
                        )
                    )

                    .offset(y: min(0, alertOffset.height))

                    .opacity(min(1, max(0, 1 - (alertOffset.height + 10.0) / -30.0)))

                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { gesture in
                            alertOffset = gesture.translation
                            dismissTask?.cancel()
                        }
                        .onEnded { _ in
                            if alertOffset.height < -30 {
                                withAnimation(.linear(duration: 0.3)) {
                                    alertOffset.height = -100
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.3))
                                    errorController.clear(animate: false)
                                }
                            } else if alertOffset == .zero {
                                if error.details != nil {
                                    detail = error
                                }
                                errorController.clear()
                            } else {
                                dismissTask?.cancel()
                                withAnimation(.spring(duration: 0.3)) {
                                    alertOffset = .zero
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.31))
                                    dismissTask = createAutoDismissTask(duration: duration)
                                }
                            }
                        }
                    )

                    .disabled(!ready)

                    .task {
                        ready = false
                        dismissTask = createAutoDismissTask(duration: duration)
                        try? await Task.sleep(for: .seconds(0.75))
                        ready = true
                    }

                    .transition(.move(edge: .top).combined(with: .opacity))

                case .none:
                    EmptyView()
                }
            }

            .alert(title: { detail in Text(detail.message) }, unwrapping: $detail) { detail in
                Button(String(localized: .localizable.errorAlertCopyToClipboard)) {
                    UIPasteboard.general.string = detail.details
                }

                Button(String(localized: .localizable.ok), role: .cancel) {}

            } message: { detail in
                Text(detail.details!)
            }

            .onReceive(errorController.$state) { value in
                if case .none = value {
                    Task {
                        try? await Task.sleep(for: .seconds(0.3))
                        alertOffset = .zero
                    }
                }
            }
    }
}

extension View {
    func errorOverlay(errorController: ErrorController) -> some View {
        modifier(ErrorDisplay(errorController: errorController))
    }
}

protocol DisplayableError: Error {
    var message: String { get }
    var details: String? { get }
}

struct GenericError: DisplayableError {
    let message: String
    let details: String?

    init(message: String, details: String? = nil) {
        self.message = message
        self.details = details
    }
}

class ErrorController: ObservableObject {
    enum State {
        case none
        case active(error: DisplayableError, duration: Double = 2.0)
    }

    @Published var state: State = .none

    var details: String? = nil

    // @TODO: Change this to localized
    private static let defaultTitle = String(localized: .localizable.errorDefaultMessage)

    func push(error: Error, message: String? = nil) {
        if let le = error as? LocalizedError {
            if let message {
                Task {
                    await push(error: GenericError(message: message, details: String(describing: error)))
                }
            } else {
                push(error: le)
            }
        } else {
            push(message: message ?? Self.defaultTitle, details: error.localizedDescription)
        }
    }

    func push(error: LocalizedError) {
        Task {
            await push(error: GenericError(message: error.errorDescription ?? Self.defaultTitle, details: error.failureReason))
        }
    }

    @MainActor
    func push(error: DisplayableError) {
        Haptics.shared.notification(.error)
        withAnimation(.spring(duration: 0.3)) {
            state = .active(error: error)
        }
    }

    func push(message: String, details: String? = nil) {
        Task {
            await push(error: GenericError(message: message, details: details))
        }
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
