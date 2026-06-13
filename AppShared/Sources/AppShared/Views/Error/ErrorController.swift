import Combine
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
  let message: String
  let details: String?
}

@MainActor
public class ErrorController: ObservableObject {
  private static let defaultTitle = String(localized: .app(.errorDefaultMessage))

  // Installed by the app shell. Returning true drops the error before it
  // becomes a user-visible toast — used for cases where another UI surface
  // already represents the condition (the connection-status banner covers
  // 401s, and connectivity errors are redundant when the offline banner is
  // already showing).
  public var shouldSuppress: ((any Error) -> Bool)?

  let subject = PassthroughSubject<any DisplayableError, Never>()

  public var presentations: AnyPublisher<any DisplayableError, Never> {
    subject.eraseToAnyPublisher()
  }

  public init() {}

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
        push(error: GenericError(message: message, details: error.localizedDescription))
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
        message: error.errorDescription ?? Self.defaultTitle,
        details: error.failureReason))
  }

  public func push(error: any DisplayableError) {
    if let shouldSuppress, shouldSuppress(error) {
      Logger.shared.debug("Suppressing error: \(String(describing: error))")
      return
    }
    Logger.shared.debug("Pushing error: \(String(describing: error))")
    Haptics.shared.notification(.error)
    subject.send(error)
  }

  public func push(message: String, details: String? = nil) {
    push(error: GenericError(message: message, details: details))
  }
}

// MARK: Previews

private struct PreviewError: LocalizedError {
  public var errorDescription: String? { String(localized: .app(.errorDefaultMessage)) }
}

public struct ErrorController_Previews: PreviewProvider {
  public struct MyButton: View {
    @EnvironmentObject var errorController: ErrorController

    public var body: some View {
      Button(String("Trigger error")) {
        errorController.push(error: PreviewError())
      }
    }
  }

  public struct Container: View {
    @StateObject var errorController = ErrorController()

    public var body: some View {
      ScrollView {
        MyButton()
        Rectangle()
          .frame(height: 300)
      }
      .errorOverlay(errorController: errorController)
      .environmentObject(errorController)
    }
  }

  public static var previews: some View {
    Container()
  }
}
