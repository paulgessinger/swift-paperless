//
//  ErrorController.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 22.04.23.
//

import Foundation
import SwiftUI

struct ErrorDisplay: ViewModifier {
    @ObservedObject var errorController: ErrorController

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let (e, d) = errorController.active {
                    ErrorView(error: e, duration: d)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                        .id(UUID())
                }
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

private struct ErrorView: View {
    var error: LocalizedError
    var duration: Double

//    var message: String {
//        let nsError = error as NSError
//        return nsError.localizedDescription
//    }

//    @State private var fraction = 0.0

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .scaleEffect(1.5)
                .labelStyle(.iconOnly)
                .padding(.trailing, 5)
            Text("\(error.localizedDescription)")
            Spacer()
        }
        .foregroundColor(.white)
        .padding(15)
        .padding(.bottom, 5)
        .edgesIgnoringSafeArea(.bottom)
        .background(Color("ErrorColor"))
//        .overlay(alignment: .bottom) {
//            HStack(alignment: .bottom) {
//                GeometryReader { geo in
//                    Rectangle().fill(Color.blue)
//                        .frame(width: fraction * geo.size.width)
//                }
//            }
//            .frame(height: 9)
//        }
//        .overlay {
//            RoundedRectangle(cornerRadius: 15)
//                .stroke(Color("ErrorColor"), lineWidth: 9)
//        }
        .clipShape(RoundedRectangle(cornerRadius: 15))
        .padding()
        .shadow(radius: 10)

//        .task {
//            withAnimation(.linear(duration: duration)) {
//                fraction = 1.0
//            }
//        }
    }
}

class ErrorController: ObservableObject {
    @Published var active: (error: LocalizedError, duration: Double)? = nil

    private var queue = DispatchQueue(label: "ErrorController")
    private static let defaultDuration = 3.0

    func push(error: Error, duration: Double = defaultDuration) {
        if let le = error as? LocalizedError {
            push(error: le, duration: duration)
        }
        else {
            push(error: GenericError(message: String(describing: error)), duration: duration)
        }
    }

    func push(message: String, duration: Double = defaultDuration) {
        push(error: GenericError(message: message), duration: duration)
    }

    func push(error: LocalizedError, duration: Double = defaultDuration) {
        queue.async {
            DispatchQueue.main.async {
                Haptics.shared.notification(.error)
                withAnimation(.easeOut) {
                    self.active = (error: error, duration: duration)
                }
            }
            Thread.sleep(forTimeInterval: duration)
            DispatchQueue.main.async {
                withAnimation(.easeOut) {
                    self.active = nil
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
    }
}

private struct PreviewError: LocalizedError {
    var errorDescription: String? { "Some kind of error ocurred! This description is a bit longer to make sure I text the layout!: \(UUID())" }
}

struct ErrorOverlay_Previews: PreviewProvider {
    struct MyButton: View {
        @EnvironmentObject var errorController: ErrorController

        var body: some View {
            Button("Trigger error") {
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
            .overlay(alignment: .bottom) {
                if let (e, d) = errorController.active {
                    ErrorView(error: e, duration: d)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                        .id(UUID())
                }
            }
            .environmentObject(errorController)
        }
    }

    static var previews: some View {
        Container()
    }
}
