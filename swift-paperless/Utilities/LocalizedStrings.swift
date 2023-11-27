import Foundation
enum LocalizedStrings {
//    enum General {
//    }

    enum Filter {
        enum DocumentType {
            static let notAssignedFilter = String(localized: "document_type_not_assigned_filter", comment: "Document type filtering")
            static let notAssignedPicker = String(localized: "document_type_not_assigned_picker", comment: "Document type filtering")
        }

        enum StoragePath {
            static let notAssignedFilter = String(localized: "storage_path_not_assigned_filter", comment: "Storage path filtering")
            static let notAssignedPicker = String(localized: "storage_path_not_assigned_picker", comment: "Storage path filtering")
        }

        enum Owner {
            static let myDocuments = String(localized: "My documents", comment: "Owner filtering")
            static let sharedWithMe = String(localized: "Shared with me", comment: "Owner filtering")
            static let unowned = String(localized: "Unowned", comment: "Owner filtering")
            static let all = String(localized: "All", comment: "Owner filtering")

            static let multipleUsers = String(localized: "Users", comment: "Number of filtered users, number is separate")

            static let notAssignedFilter = String(localized: "owner_not_assigned_filter", comment: "Owner filtering")
            static let notAssignedPicker = String(localized: "owner_not_assigned_picker", comment: "Owner filtering")
        }

        enum Tags {
            static let notAssignedFilter = String(localized: "tags_not_assigned_filter", comment: "Tags filterings")
            static let notAssignedPicker = String(localized: "tags_not_assigned_picker", comment: "Tags filterings")

            static let all = String(localized: "All", comment: "Tags filterings")
            static let any = String(localized: "No filter", comment: "Tags filterings")
        }
    }

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
        static let title = String(localized: "settings.title")

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
