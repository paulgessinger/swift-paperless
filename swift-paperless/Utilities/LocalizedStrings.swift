enum LocalizedStrings {
//    enum General {
//    }

    enum Filter {
        enum Correspondent {
            static let notAssignedFilter = String(localized: "None")
            static let notAssignedPicker = String(localized: "Not assigned")
        }

        enum DocumentType {
            static let notAssignedFilter = String(localized: "None")
            static let notAssignedPicker = String(localized: "Not assigned")
        }

        enum StoragePath {
            static let notAssignedFilter = String(localized: "None")
            static let notAssignedPicker = String(localized: "Not assigned")
        }

        enum Owner {
            static let myDocuments = String(localized: "My documents", comment: "Owner filtering")
            static let sharedWithMe = String(localized: "Shared with me", comment: "Owner filtering")
            static let unowned = String(localized: "Unowned", comment: "Owner filtering")
            static let all = String(localized: "All", comment: "Owner filtering")

            static let multipleUsers = String(localized: "Users", comment: "Number of filtered users, number is separate")

            static let notAssignedFilter = String(localized: "None")
            static let notAssignedPicker = String(localized: "Not assigned")
        }

        enum Tags {
            static let notAssignedFilter = String(localized: "None")
            static let notAssignedPicker = String(localized: "Not assigned")
        }
    }
}
