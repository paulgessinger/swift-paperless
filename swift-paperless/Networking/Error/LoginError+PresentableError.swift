//
//  LoginError+PresentableError.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 14.12.2024.
//

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

        case .invalidLogin:
            Text(.login(.errorLoginInvalidDetails))

        case .invalidToken:
            Text(.login(.errorMessage))

        case let .request(error):
            augment(error: error)

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
        case let .unexpectedStatusCode(code, _) where code == 403:
            // In the login scenario, a 403 can indicate that the user has auto login configured.
            error.presentation
            Text(.login(.autologinHint))

        case let .unexpectedStatusCode(code, _) where code == 400:
            // Bad request can indicate mTLS issues
            error.presentation
            Text(.login(.errorBadRequest))

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
            h(.invalidLogin)
            h(.request(.unexpectedStatusCode(code: 123, detail: "Detail string")))
            h(.request(.unexpectedStatusCode(code: 123, detail: nil)))
            h(.request(.unexpectedStatusCode(code: 403, detail: nil)))
            h(.request(.unexpectedStatusCode(code: 400, detail: nil)))
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
