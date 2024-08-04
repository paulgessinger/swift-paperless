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
}

enum LoginError: DisplayableError {
    case invalidUrl(_: LocalizedError?)
    case invalidLogin

    case invalidResponse(statusCode: Int, details: String?)
    case localNetworkDenied

    case insufficientPermissions

    // Includes the upstream error because we want to show that extra info
    case certificate(_: Error)

    case other(_: Error)
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
            if let desc = error?.errorDescription {
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

        case .localNetworkDenied:
            return loc(.login(.errorLocalNetworkDenied))

        case .insufficientPermissions:
            return loc(.login(.errorInsufficientPermissions))

        case let .other(error):
            return AttributedString((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)

        case let .certificate(error):
            let msg = loc(.login(.errorCertificate))
            let err: String
            switch error {
            case let error as LocalizedError:
                err = error.errorDescription ?? error.localizedDescription
            default:
                err = error.localizedDescription
            }

            return try? AttributedString(markdown: "\(msg):\n\(err)")
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
    private func errorBlock(_ error: Error) -> some View {
        let desc = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

        Text(desc)
            .italic()
    }

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

        case let .invalidUrl(error):
            (Text(.login(.errorUrlInvalid)) + Text(":"))
                .bold()
            if let desc = error?.errorDescription {
                Text(desc)
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

            errorBlock(error)

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

    var view: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "xmark")
                .font(.footnote)
            VStack(alignment: .leading) {
                inner
            }
            .font(.footnote)
        }
        .foregroundColor(.red)
    }
}

// - MARK: Preview

private func h(_ error: LoginError) -> some View {
    error.view
}

private struct TestError: Error {}

private struct TestLocalizedError: LocalizedError {
    var errorDescription: String? = "Localized description"
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        h(.invalidUrl(TestLocalizedError()))
        h(.invalidLogin)
        h(.invalidResponse(statusCode: 123, details: "Detail string"))
        h(.invalidResponse(statusCode: 123, details: nil))
        h(.insufficientPermissions)
        h(.certificate(TestError()))
        h(.certificate(TestLocalizedError()))
        h(.other(TestError()))
        h(.other(TestLocalizedError()))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
}
