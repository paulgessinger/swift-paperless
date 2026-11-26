import SafariServices
import SwiftUI
import UIKit

private struct InAppBrowserLinks: ViewModifier {
  func body(content: Content) -> some View {
    content.environment(
      \.openURL,
      OpenURLAction { url in
        guard ["http", "https"].contains(url.scheme?.lowercased()),
          let presenter = UIApplication.shared.topViewController
        else {
          return .systemAction
        }
        presenter.present(SFSafariViewController(url: url), animated: true)
        return .handled
      })
  }
}

extension View {
  /// Opens web links in a Safari sheet instead of the browser app. Other
  /// schemes, such as `mailto:`, go to the system.
  func inAppBrowserLinks() -> some View {
    modifier(InAppBrowserLinks())
  }
}

extension UIApplication {
  /// The view controller on top of the foreground window. It is the one that
  /// can present, since SwiftUI covers and sheets sit above the root.
  fileprivate var topViewController: UIViewController? {
    let scene =
      connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    var top = scene?.keyWindow?.rootViewController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }
}
