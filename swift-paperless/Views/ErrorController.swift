import Foundation
import SwiftUI

struct ErrorDisplay: ViewModifier {
    @ObservedObject var errorController: ErrorController
    @State private var detail: DisplayableError? = nil
    @State private var alertOffset = CGSize.zero
    @State private var dragInitiated = false

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
                                Text("Tap for details!")
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
                            dragInitiated = true
                        }
                        .onEnded({ _ in
                            print("Drag end \(alertOffset)")
                            if alertOffset.height < -30 {
                                print("Clear only")
                                withAnimation(.linear(duration: 0.3)) {
                                    alertOffset.height = -100
                                }
                                Task {
                                    try? await Task.sleep(for: .seconds(0.3))
                                    errorController.clear(animate: false)
                                }
                            } else if alertOffset == .zero {
                                print("Clear and how")
                                if error.details != nil {
                                    detail = error
                                }
                                errorController.clear()
                            } else {
                                print("Animate back")
                                withAnimation(.spring) {
                                    alertOffset = .zero
                                }
                            }
                        }
                        ))

                    .task {
                        try? await Task.sleep(for: .seconds(duration))
                        print(alertOffset)
                        if alertOffset == .zero, !dragInitiated {
                            errorController.clear()
                        }
                    }

                    .transition(.move(edge: .top).combined(with: .opacity))

                case .none:
                    EmptyView()
                }
            }

            .alert(title: { detail in Text(detail.message) }, unwrapping: $detail,
                   actions: { detail in

                       Button("Copy to clipboard") {
                           UIPasteboard.general.string = detail.details
                       }

                       Button("Ok", role: .cancel) {}

                   },
                   message: { detail in Text(detail.details!) })

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
    private static let defaultTitle = "An error occurred"

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
            push(message: message ?? Self.defaultTitle, details: String(describing: error))
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

private struct PreviewError: LocalizedError {
    var errorDescription: String? { "Some kind of error ocurred!" }
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
