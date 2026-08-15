//
//  ErrorDisplay.swift
//  swift-paperless
//
//  Bridges ErrorController into the swiftui-toasts presentation system.
//  Must be installed inside a parent that called `.installToast(...)`.
//

import Common
import SwiftUI
import Toasts
import WindowOverlay

public struct ErrorDisplay: ViewModifier {
  @ObservedObject public var errorController: ErrorController
  @Environment(\.presentToast) private var presentToast

  @State private var detail: (any DisplayableError)? = nil

  public init(errorController: ErrorController) {
    self.errorController = errorController
  }

  public func body(content: Content) -> some View {
    content
      .onReceive(errorController.presentations) { error in
        let button: ToastButton? =
          error.details == nil
          ? nil
          : ToastButton(
            title: String(localized: .app(.errorAlertTapForDetails)),
            color: .orange,
            action: { detail = error }
          )
        presentToast(
          ToastValue(
            icon: Image(systemName: "exclamationmark.triangle.fill")
              .foregroundStyle(.red),
            message: error.message,
            button: button,
            duration: 5.0
          )
        )
      }
      // Host the detail alert in a dedicated window (the same mechanism the
      // toast itself uses) so it presents above whatever sheet is currently
      // open. A plain `.alert` here attaches to the root view controller, and
      // presenting it tears down any active sheet (e.g. Settings).
      .windowOverlay(isPresented: detail != nil) {
        Color.clear
          .alert(
            unwrapping: $detail,
            title: { detail in
              Text(detail.message)
            },
            actions: { ErrorAlertActions(for: $0) },
            message: { detail in
              if let details = detail.details {
                Text(details)
              }
            }
          )
      }
  }
}

extension View {
  @MainActor public func errorOverlay(errorController: ErrorController) -> some View {
    modifier(ErrorDisplay(errorController: errorController))
  }
}

/// The buttons an error alert offers: copy the details, follow the
/// documentation link, dismiss. Shared with the Share Extension's alert so the
/// two stay in the same vocabulary.
public struct ErrorAlertActions: View {
  private let error: any DisplayableError

  public init(for error: any DisplayableError) {
    self.error = error
  }

  public var body: some View {
    // The app only reaches this alert when there are details to show; the
    // extension alerts on every error, so the button is conditional.
    if error.details != nil {
      Button(String(localized: .app(.copyToClipboard))) {
        Pasteboard.general.string = error.details
      }
    }

    if let link = error.documentationLink {
      Link(String(localized: .app(.errorMoreInfo)), destination: link)
    }

    Button(String(localized: .app(.ok)), role: .cancel) {}
  }
}
