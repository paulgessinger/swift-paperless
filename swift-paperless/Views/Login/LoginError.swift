//
//  LoginError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 03.08.2024.
//

import Foundation
import SwiftUI

enum UrlError: LocalizedError {
    case invalidScheme(_: String)
    case other
    case cannotSplit
    case emptyHost

    var errorDescription: String? {
        switch self {
        case let .invalidScheme(scheme):
            "Invalid scheme: \(scheme)"
        case .other: "other"
        case .cannotSplit: "cannot split"
        case .emptyHost: "empty host"
        }
    }
}

enum LoginError: DisplayableError, Equatable {
    case invalidUrl(_: String?)
    case invalidLogin

    case invalidResponse(statusCode: Int, details: String?)

    case badRequest

    case localNetworkDenied

    case insufficientPermissions

    case certificate(_: String)

    case other(_: String)

    private static func string(for error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    init(other error: any Error) { self = .other(Self.string(for: error)) }
    init(invalidUrl error: any Error) {
        if let error = error as? any LocalizedError {
            self = .invalidUrl(Self.string(for: error))
        } else {
            self = .invalidUrl(nil)
        }
    }

    init(certificate error: any Error) { self = .certificate(Self.string(for: error)) }
}

extension LoginError {
    var message: String {
        String(localized: .login(.errorMessage))
    }

    var details: String? {
        if let detailsAttributed {
            String(detailsAttributed.characters)
        } else {
            nil
        }
    }

    var detailsAttributed: AttributedString? {
        let loc: (LocalizedStringResource) -> AttributedString = { s in AttributedString(localized: s) }
        switch self {
        case let .invalidUrl(error):
            var msg = String(localized: .login(.errorUrlInvalid))
            if let desc = error {
                msg = "\(msg) Details: \(desc)"
            }
            return try? AttributedString(markdown: msg)

        case .invalidLogin:
            return loc(.login(.errorLoginInvalid))

        case let .invalidResponse(statusCode, details):
            var msg = String(localized: .login(.errorInvalidResponse(statusCode)))
            if let details {
                msg = "\(msg) Details: \(details)"
            }
            return try? AttributedString(markdown: msg)

        case .badRequest:
            let msg = String(localized: .login(.errorInvalidResponse(400))) + String(localized: .login(.errorBadRequest))

            return try? AttributedString(markdown: msg)

        case .localNetworkDenied:
            return loc(.login(.errorLocalNetworkDenied))

        case .insufficientPermissions:
            return loc(.login(.errorInsufficientPermissions))

        case let .other(error):
            return AttributedString(error)

        case let .certificate(error):
            let msg = loc(.login(.errorCertificate))
            return try? AttributedString(markdown: "\(msg):\n\(error)")
        }
    }

    var documentationLink: URL? {
        switch self {
        case .localNetworkDenied:
            DocumentationLinks.localNetworkDenied
        case .insufficientPermissions:
            DocumentationLinks.insufficientPermissions
        case .certificate:
            DocumentationLinks.certificate
        default:
            nil
        }
    }
}

extension LoginError {
    @ViewBuilder
    private var inner: some View {
        switch self {
        case let .invalidResponse(code, details):
            Text(.login(.errorInvalidResponse(code)))
                .bold()

            if let details {
                Text(details)
                    .italic()
            }

        case .badRequest:
            VStack(alignment: .leading) {
                Text(.login(.errorInvalidResponse(400)))
                    .bold()
                Text(.login(.errorBadRequest))
            }

        case let .invalidUrl(error):
            (Text(.login(.errorUrlInvalid)) + Text(":"))
                .bold()
            if let error {
                Text(error)
            }

        case .invalidLogin:
            (Text(.login(.errorLoginInvalid)) + Text(":"))
                .bold()
            Text(.login(.errorLoginInvalidDetails))

        case .insufficientPermissions:
            (Text(.login(.errorInsufficientPermissions)) + Text(":"))
                .bold()
            Text(.login(.errorInsufficientPermissionsDetail))

        case let .certificate(error):
            (Text(.login(.errorCertificate)) + Text(":"))
                .bold()

            Text(error)
                .italic()

            Text(.login(.certificateInfo))
                .bold()

        default:
            if let detailsAttributed {
                Text(detailsAttributed)
                    .fixedSize(horizontal: false, vertical: true)
                    .bold()
            } else {
                Text(.login(.errorMessage))
                    .fixedSize(horizontal: false, vertical: true)
                    .bold()
            }
        }

        if let link = documentationLink {
            Link(destination: link) {
                Text(.login(.documentationLinkLabel))
                    .underline()
            }
        }
    }

    @MainActor
    var view: some View {
        LoginFooterView(systemImage: "xmark") {
            inner
        }
        .foregroundColor(.red)
    }
}

// - MARK: Preview

@MainActor
private func h(_ error: LoginError) -> some View {
    error.view
}

private struct TestError: Error {}

private struct TestLocalizedError: LocalizedError {
    var errorDescription: String? = "Localized description"
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        h(.init(invalidUrl: TestLocalizedError()))
        h(.invalidLogin)
        h(.invalidResponse(statusCode: 123, details: "Detail string"))
        h(.invalidResponse(statusCode: 123, details: nil))
        h(.insufficientPermissions)
        h(.init(certificate: TestError()))
        h(.init(certificate: TestLocalizedError()))
        h(.init(other: TestError()))
        h(.init(other: TestLocalizedError()))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
}
