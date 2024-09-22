import Foundation
import os

func deriveUrl(string value: String, suffix: String = "") throws(UrlError) -> (base: URL, resolved: URL) {
    let url: URL?

    let pattern = /(\w+):\/\/(.*)/

    if let matches = try? pattern.wholeMatch(in: value) {
        let scheme = matches.1
        let rest = matches.2
        if scheme != "http", scheme != "https" {
            Logger.shared.error("Encountered invalid scheme \(scheme)")
            throw .invalidScheme(String(scheme))
        }
        url = URL(string: "\(scheme)://\(rest)")
    } else {
        url = URL(string: "https://\(value)")
    }

    guard let url, var url = URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
        Logger.shared.notice("Derived URL \(value) was invalid")
        throw .other
    }

    let base = url

    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        Logger.shared.notice("Could not parse URL \(url) into components")
        throw .cannotSplit
    }

    guard let host = components.host, !host.isEmpty else {
        Logger.shared.error("URL \(url) had empty host")
        throw .emptyHost
    }

    assert(components.scheme != nil)

    url = url.appending(component: "api", directoryHint: .isDirectory)
    if !suffix.isEmpty {
        url = url.appending(component: suffix, directoryHint: .isDirectory)
    }

    Logger.shared.notice("Derive URL: \(value) + \(suffix) -> \(url)")

    return (base, url)
}
