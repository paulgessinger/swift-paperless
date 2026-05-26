import AsyncAlgorithms
import Foundation
import SwiftUI
import os

public protocol DisplayableError: Error, DocumentedError {
  var message: String { get }
  var details: String? { get }
}

extension DisplayableError {
  public var documentationLink: URL? { nil }
}

private struct GenericError: DisplayableError {
  public let message: String
  public let details: String?

  public init(message: String, details: String? = nil) {
    self.message = message
    self.details = details
  }
}

@MainActor
public class ErrorController: ObservableObject {
  public enum State {
    case none
    case active(error: any DisplayableError, duration: Double)
  }

  @Published public var state: State = .none

  private static let defaultTitle = String(localized: .app(.errorDefaultMessage))

  // Installed by the app shell. Returning true drops the error before it
  // becomes a user-visible banner — used for cases where another UI surface
  // already represents the condition (the connection-status banner covers
  // 401s, and connectivity errors are redundant when the offline banner is
  // already showing).
  public var shouldSuppress: ((any Error) -> Bool)?

  private var channel = AsyncChannel<any DisplayableError>()
  private var task: Task<Void, Never>? = nil

  public init() {
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

  public func push(error: any Error, message: String? = nil) {
    if let shouldSuppress, shouldSuppress(error) {
      Logger.shared.debug("Suppressing error: \(String(describing: error))")
      return
    }
    if let de = error as? any DisplayableError {
      push(error: de)
      return
    }

    if let le = error as? any LocalizedError {
      if let message {
        Logger.shared.error("Presenting error: \(String(describing: error))")
        Task {
          push(error: GenericError(message: message, details: error.localizedDescription))
        }
      } else {
        push(error: le)
      }
      return
    }
    Logger.shared.error("Presenting error: \(String(describing: error))")
    push(message: message ?? Self.defaultTitle, details: error.localizedDescription)
  }

  public func push(error: any Error, message: LocalizedStringResource) {
    push(error: error, message: String(localized: message))
  }

  public func push(error: any LocalizedError) {
    push(
      error: GenericError(
        message: error.errorDescription ?? Self.defaultTitle, details: error.failureReason))
  }

  public func push(error: any DisplayableError) {
    if let shouldSuppress, shouldSuppress(error) {
      Logger.shared.debug("Suppressing error: \(String(describing: error))")
      return
    }
    Task { @MainActor in
      await channel.send(error)
    }
  }

  public func push(message: String, details: String? = nil) {
    push(error: GenericError(message: message, details: details))
  }

  public func clear(animate: Bool = true) {
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
  public var errorDescription: String? { String(localized: .app(.errorDefaultMessage)) }
}

public struct ErrorOverlay_Previews: PreviewProvider {
  public struct MyButton: View {
    @EnvironmentObject var errorController: ErrorController

    public var body: some View {
      Button(String("Trigger error")) {
        errorController.push(error: PreviewError())
      }
    }
  }

  public struct Container: View {
    //        @State var error: LocalizedError? = PreviewError()

    @StateObject var errorController = ErrorController()

    public var body: some View {
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

  public static var previews: some View {
    Container()
  }
}
