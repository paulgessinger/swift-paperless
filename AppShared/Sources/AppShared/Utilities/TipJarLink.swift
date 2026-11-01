import Foundation

/// The public tip link. Browsers get the landing page; the app shows the tip
/// jar instead, so release notes can use the same link everywhere.
public enum TipJarLink {
  public static let url = URL(string: "https://swift-paperless.app/tip")!

  public static func matches(_ candidate: URL) -> Bool {
    guard let components = URLComponents(url: candidate, resolvingAgainstBaseURL: true) else {
      return false
    }

    let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
    return components.scheme == url.scheme && components.host == url.host() && path == url.path()
  }
}
