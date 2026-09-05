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

struct GenericError: DisplayableError {
  let message: String
  let details: String?
}

@MainActor
public class ErrorController: ObservableObject {
  static let defaultTitle = String(localized: .app(.errorDefaultMessage))

  // Installed by the app shell. Returning true drops the error before it
  // becomes a user-visible toast — used for cases where another UI surface
  // already represents the condition (the connection-status banner covers
  // 401s, and connectivity errors are redundant when the offline banner is
  // already showing).
  public var shouldSuppress: ((any Error) -> Bool)?

  // Installed by the app shell alongside `shouldSuppress`. Lets the
  // user-initiated entry points (`UserInitiatedErrors.swift`) tell "this
  // device has no link" from "this server didn't answer" without every call
  // site having to reach for the NetworkMonitor itself.
  public var isOffline: (() -> Bool)?

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
    present(displayable(for: error, message: message))
  }

  /// The banner an arbitrary error turns into, with no suppression policy
  /// applied. Shared with the user-initiated entry points, which reuse the
  /// conversion but not the policy.
  func displayable(for error: any Error, message: String?) -> any DisplayableError {
    if let de = error as? any DisplayableError {
      return de
    }
    if let le = error as? any LocalizedError {
      if let message {
        Logger.shared.error("Presenting error: \(String(describing: error))")
        return GenericError(message: message, details: error.localizedDescription)
      }
      return GenericError(
        message: le.errorDescription ?? Self.defaultTitle,
        details: le.failureReason)
    }
    Logger.shared.error("Presenting error: \(String(describing: error))")
    return GenericError(message: message ?? Self.defaultTitle, details: error.localizedDescription)
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
    present(error)
  }

  /// Hand the error to the display bridge unconditionally. Bypasses
  /// `shouldSuppress`, so only the entry points above — which have already
  /// decided the error is worth showing — may call it.
  func present(_ error: any DisplayableError) {
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
