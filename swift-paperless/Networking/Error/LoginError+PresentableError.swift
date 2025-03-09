//
//  LoginError+PresentableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.12.2024.
//

import Networking
import SwiftUI

extension LoginError: PresentableError {
    @ViewBuilder
    var presentation: some View {
        switch self {
        case let .invalidUrl(error):
            (Text(.login(.errorUrlInvalid)) + Text(":"))
                .bold()
            if let desc = error.errorDescription {
                Text(desc)
                    .italic()
            }

        case let .invalidLogin(details):
            Text(.login(.errorLoginInvalidDetails))
            if let details {
                Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                    + (Text(details).italic())
            }

        case .invalidToken:
            Text(.login(.errorMessage))

        case let .request(error):
            augment(error: error)

        case .otpRequired:
            // This should always work, but don't crash
            Text(details ?? "invalid")

        case let .other(error):
            Text(.login(.errorMessage))
                .fixedSize(horizontal: false, vertical: true)
                .bold()
            Text(.localizable(.requestErrorDetailLabel)) + Text(": ")
                + Text(error)
                .italic()
        }

        if let link = documentationLink {
            Link(destination: link) {
                Text(.login(.documentationLinkLabel))
                    .underline()
            }
        }
    }

    @ViewBuilder
    private func augment(error: RequestError) -> some View {
        // This handles a few special cases where status code have special meaning in the login process.
        // In some cases: augment the generale request error message

        switch error {
        case let .unexpectedStatusCode(code, _) where code == .forbidden:
            // In the login scenario, a 403 can indicate that the user has auto login configured.
            error.presentation
            Text(.login(.autologinHint))

        case .forbidden:
            error.presentation
            Text(.login(.errorInsufficientPermissionsDetail))

        case .certificate:
            error.presentation
            Text(.login(.certificateInfo))
                .bold()

        default:
            // Fully defer to RequestError for presentation
            error.presentation
        }
    }
}

// - MARK: Preview

@MainActor
private func h(_ error: LoginError) -> some View {
    error.presentation
}

private struct TestError: Error {}

private struct TestLocalizedError: LocalizedError {
    var errorDescription: String? = "Localized description"
}

#Preview {
    ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 10) {
            h(.invalidUrl(.emptyHost))
            h(.invalidLogin(detail: "MFA bla bla bla"))
            h(.request(.unexpectedStatusCode(code: .imATeapot, detail: "Detail string")))
            h(.request(.unexpectedStatusCode(code: .imATeapot, detail: nil)))
            h(.request(.unexpectedStatusCode(code: .forbidden, detail: nil)))
            h(.request(.unexpectedStatusCode(code: .badRequest, detail: nil)))
            h(.request(.forbidden(detail: "Blubb")))
            h(.init(certificate: TestError()))
            h(.init(certificate: TestLocalizedError()))
            h(.init(other: TestError()))
            h(.init(other: TestLocalizedError()))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
