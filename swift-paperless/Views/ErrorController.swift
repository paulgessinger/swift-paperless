import AlertToast
import Foundation
import SwiftUI

struct ErrorDisplay: ViewModifier {
    @ObservedObject var errorController: ErrorController
    @State private var showDetails = false

    func body(content: Content) -> some View {
        content
            .toast(isPresenting: $errorController.show, offsetY: 5) {
                errorController.toast ?? AlertToast(type: .regular, title: "None")
            } onTap: {
                if errorController.details != nil {
                    showDetails = true
                }
            }
            completion: {
                errorController.toast = nil
                errorController.details = nil
            }

            .alert(errorController.details ?? String(""), isPresented: $showDetails) {
                Button("Copy to clipboard") {
                    UIPasteboard.general.string = errorController.details
                }
                Button("Ok", role: .cancel) {}
            }
    }
}

extension View {
    func errorOverlay(errorController: ErrorController) -> some View {
        return modifier(ErrorDisplay(errorController: errorController))
    }
}

struct GenericError: LocalizedError {
    let message: String

    var errorDescription: String? { return message }
}

class ErrorController: ObservableObject {
    @Published var show: Bool = false
    @Published var toast: AlertToast? = nil // = AlertToast(type: .regular, title: "None")
    @Published var details: String? = nil

//    @Published var active: (error: LocalizedError, duration: Double)? = nil
//
//    private var queue = DispatchQueue(label: "ErrorController")
//    private static let defaultDuration = 3.0

    private static let defaultTitle = "An error occurred"

    func push(error: Error, title: String? = nil) {
        if let le = error as? LocalizedError {
            push(error: le, title: title)
        }
        else {
            push(title: title ?? Self.defaultTitle, details: String(describing: error))
        }
    }

    func push(error: LocalizedError, title: String? = nil) {
        push(title: title ?? Self.defaultTitle, details: error.errorDescription)
    }

    func push(title: String, details: String? = nil) {
        toast = AlertToast(displayMode: .hud, type: .error(.red),
                           title: title, subTitle: details != nil ? "Tap for more information" : nil)
        self.details = details
        // who knows why this is needed
        withAnimation { show = true }
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
