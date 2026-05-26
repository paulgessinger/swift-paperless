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
      .alert(
        unwrapping: $detail,
        title: { detail in
          Text(detail.message)
        },
        actions: { detail in
          Button(String(localized: .app(.copyToClipboard))) {
            Pasteboard.general.string = detail.details
          }

          if let link = detail.documentationLink {
            Link(String(localized: .app(.errorMoreInfo)), destination: link)
          }

          Button(String(localized: .app(.ok)), role: .cancel) {}
        },
        message: { detail in
          if let details = detail.details {
            Text(details)
          }
        }
      )
  }
}

extension View {
  @MainActor public func errorOverlay(errorController: ErrorController) -> some View {
    modifier(ErrorDisplay(errorController: errorController))
  }
}
