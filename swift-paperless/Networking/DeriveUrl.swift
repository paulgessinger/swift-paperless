import Foundation
import os

func deriveUrl(string value: String, suffix: String = "") -> (base: URL, resolved: URL)? {
    let url: URL?

    let pattern = /https?:\/\/(.*)/

    if (try? pattern.wholeMatch(in: value)) != nil {
        url = URL(string: value)
    } else {
        url = URL(string: "https://\(value)")
    }

    guard var url = url else {
        Logger.shared.debug("Derived url \(value) was invalid")
        return nil
    }

    let base = url

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        // @TODO: Add proper error handling
        Logger.shared.debug("Could not parse URL \(url) into components")
        return nil
    }

    guard let host = components.host, !host.isEmpty else {
        // @TODO: Add proper error handling
        Logger.shared.debug("URL \(url) had empty host")
        return nil
    }

    assert(components.scheme != nil)

    url = url.appending(component: "api", directoryHint: .isDirectory)
    if !suffix.isEmpty {
        url = url.appending(component: suffix, directoryHint: .isDirectory)
    }

    Logger.shared.trace("Derive url: \(value) + \(suffix) -> \(url)")

    return (base, url)
}
