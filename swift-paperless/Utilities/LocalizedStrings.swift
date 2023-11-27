import Foundation
import SwiftUI

enum LocalizedStrings {
//    enum General {
//    }

    enum Login {
        static let moreToolbarButtonLabel = String(localized: "login.more_toolbar_button_label", comment: "Login")
        static let extraHeaders = AttributedString(localized: "login.extra_headers", comment: "Login")
        static let detailsTitle = String(localized: "login.details_title", comment: "Login")
        enum PaperlessUrl {
            static let placeholder = String(localized: "login.paperless_url.placeholder", comment: "Login paperless_url")
            static let valid = String(localized: "login.paperless_url.valid", comment: "Login paperless_url")
            static let error = String(localized: "login.paperless_url.error", comment: "Login paperless_url")
        }

        static let username = String(localized: "login.username", comment: "Login")
        static let password = String(localized: "login.password", comment: "Login")
        static let credentials = String(localized: "login.credentials", comment: "Login")
        static let passwordStorageNotice = String(localized: "login.password_storage_notice", comment: "Login")
        static let apiInUrlNotice = AttributedString(localized: "login.api_in_url_notice", comment: "Login")
        static let httpWarning = AttributedString(localized: "login.http_warning", comment: "Login")
        enum LoginButton {
            static let label = String(localized: "login.login_button.label", comment: "Login login_button")
            static let valid = String(localized: "login.login_button.valid", comment: "Login login_button")
            static let error = String(localized: "login.login_button.error", comment: "Login login_button")
        }
    }

    enum Settings {
        static let organization = String(localized: "settings.organization.title")

        static let preferences = String(localized: "settings.preferences.title")

        static let advanced = String(localized: "settings.advanced.title")

        enum Details {
            static let title = String(localized: "settings.details.title")

            static let libraries = String(localized: "settings.libraries.title")
            static let librariesLoadError = String(localized: "settings.details.libraries.load_error")

            static let sourceCode = String(localized: "settings.details.source_code")

            static let privacy = String(localized: "settings.details.privacy")
            static let privacyLoadError = { (url: String) in String(localized: "settings.details.privacy.load_error \(url)") }

            static let feedback = String(localized: "settings.details.feedback")
        }

        static let documentDeleteConfirmationLabel = String(localized: "settings.preferences.document_delete_confirmation_label", comment: "Preferences")
        static let documentDeleteConfirmationDescription = String(localized: "settings.preferences.document_delete_confirmation_description", comment: "Preferences")
    }
}
