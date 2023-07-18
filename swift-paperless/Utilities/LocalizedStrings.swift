enum LocalizedStrings {
//    enum General {
//    }

    enum Filter {
        enum Correspondent {
            static let notAssignedFilter = String(localized: "correspondent_not_assigned_filter", comment: "Correspondent filtering")
            static let notAssignedPicker = String(localized: "correspondent_not_assigned_picker", comment: "Correspondent filtering")
        }

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
}
