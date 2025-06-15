//
//  CustomFieldEditView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.25.
//

import Common
import DataModel
import Networking
import SwiftUI

struct CustomFieldEditView: View {
    @Binding var document: Document
    @State private var customFields: [CustomFieldInstance] = []

    @EnvironmentObject var store: DocumentStore
    @Environment(\.locale) private var locale

    init(document: Binding<Document>, store _: DocumentStore) {
        _document = document
    }

    @ViewBuilder
    private func invalidFieldView(instance: CustomFieldInstance, reason: CustomFieldValue.InvalidReason) -> some View {
        // @TODO: Add localized explanations
        Group {
            switch reason {
            case let .invalidDate(date):
                Text("\(instance.field.name) Invalid date: \(date)")
            case let .invalidURL(url):
                Text("\(instance.field.name) Invalid URL: \(url)")
            case let .invalidMonetary(value):
                Text("\(instance.field.name) Invalid monetary value: \(value)")
            case let .invalidSelectOption(option):
                Text("\(instance.field.name) Invalid select option: \(option)")
            case .unknownValue:
                Text("\(instance.field.name) Unknown value type")
            case let .unknownDataType(dataType):
                Text("\(instance.field.name) Unknown data type: \(dataType)")
            case let .typeMismatch(dataType, rawValue):
                Text("\(instance.field.name) Type mismatch: expected \(String(describing: dataType)) got: \(String(describing: rawValue))")
            }
        }
        .foregroundStyle(.red)
    }

    @ViewBuilder
    private func fieldView(index: Int, field: Binding<CustomFieldInstance>) throws -> some View {
        if case let .invalid(reason) = field.wrappedValue.value {
            // @TODO: Make pretty with icon and better text
            Section(field.wrappedValue.field.name) {
                invalidFieldView(instance: field.wrappedValue, reason: reason)
            }
        } else {
            Group {
                switch field.wrappedValue.field.dataType {
                case .string:
                    StringView(instance: field)
                case .float:
                    FloatView(instance: field)
                case .boolean:
                    BooleanView(instance: field)
                case .integer:
                    IntegerView(instance: field)
                case .date:
                    DateView(instance: field)
                case .monetary:
                    MonetaryView(instance: field)
                case .url:
                    UrlView(instance: field)
                case .documentLink:
                    DocumentLinkView(instance: field)
                case .select:
                    SelectView(instance: field)
                case let .other(dataType):
                    // Theoretically this should never happen because we catch this above if the value is invalid
                    invalidFieldView(instance: field.wrappedValue, reason: .unknownDataType(dataType))
                }
            }
            .swipeActions {
                Button("Delete") {
                    print("Delete: \(index)")
                }
            }
        }
    }

    var body: some View {
        Form {
            if customFields.hasInvalidValues {
                Section {
                    Text("Has some invalid custom fields, please fix them.")
                        .foregroundStyle(.red)
                }
            }

            ForEach(0 ..< customFields.count, id: \.self) { index in
                let field = $customFields[index]
                try? fieldView(index: index, field: field)
            }

            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                Section("decoded") {
                    ForEach(customFields, id: \.self) { field in
                        VStack(alignment: .leading) {
                            Text("\(field.field.name) (#\(field.field.id))").bold()
                            Text(String(describing: field.value))
                        }
                    }
                }

                Section("raw") {
                    ForEach(document.customFields, id: \.self) { entry in
                        VStack(alignment: .leading) {
                            let field = customFields.first { $0.field.id == entry.field }?.field.name ?? "Unknown Field"
                            Text("#\(entry.field) (\(field))").bold()
                            Text(String(describing: entry.value))
                        }
                    }
                }
            }
        }
        .task {
            if customFields.isEmpty {
                customFields = [CustomFieldInstance].fromRawEntries(
                    document.customFields.values, customFields: store.customFields, locale: locale
                )
            }
        }

        .onChange(of: customFields) {
            document.customFields = customFields.rawEntries
        }
    }
}

// - MARK: Previews

private struct PreviewHelper: View {
    @EnvironmentObject var store: DocumentStore
    @State var document: Document?
    @State var navPath = NavigationPath()

    let instances: [CustomFieldInstance]
    let customFields: [CustomField]

    init() {
        customFields = [
            CustomField(id: 1, name: "Custom float", dataType: .float),
            CustomField(id: 2, name: "Custom bool", dataType: .boolean),
            CustomField(id: 4, name: "Custom integer", dataType: .integer),
            CustomField(id: 7, name: "Custom string", dataType: .string),
            CustomField(id: 3, name: "Custom date", dataType: .date),
            CustomField(id: 6, name: "Local currency", dataType: .monetary), // No default currency
            CustomField(
                id: 5, name: "Default USD", dataType: .monetary,
                extraData: .init(defaultCurrency: "USD")
            ), // Default currency
            CustomField(id: 8, name: "Custom url", dataType: .url),
            CustomField(id: 9, name: "Custom doc link", dataType: .documentLink),
            CustomField(
                id: 10, name: "Custom select", dataType: .select,
                extraData: .init(selectOptions: [
                    .init(id: "aa", label: "Option A"),
                    .init(id: "bb", label: "Option B"),
                    .init(id: "cc", label: "Option C"),
                ])
            ),
            CustomField(id: 11, name: "Unknown field", dataType: .other("plumbus")),
        ]

        instances = [
            // Invalid because we don't understand the field data type
            CustomFieldInstance(field: customFields[10], value: .float(123.45)),
            // Invalid because we don't understand the value that came from the backend
            CustomFieldInstance(field: customFields[3], value: .invalid(.unknownValue)),
            // Invalid because the type we got from the backend is not what we expected
            CustomFieldInstance(field: customFields[2], value: .float(123.45)),

            CustomFieldInstance(field: customFields[8], value: .documentLink([])),
            CustomFieldInstance(
                field: customFields[9], value: .select(.init(id: "bb", label: "Option B"))
            ),
            CustomFieldInstance(field: customFields[0], value: .float(123.45)),
            CustomFieldInstance(field: customFields[1], value: .boolean(true)),
            CustomFieldInstance(field: customFields[2], value: .integer(123)),
            CustomFieldInstance(field: customFields[3], value: .string("Hello")),
            CustomFieldInstance(field: customFields[4], value: .date(Date())),
            CustomFieldInstance(
                field: customFields[5], value: .monetary(currency: "USD", amount: 1000.00)
            ),
            CustomFieldInstance(
                field: customFields[6], value: .monetary(currency: "CHF", amount: 1000.00)
            ),
            CustomFieldInstance(
                field: customFields[7], value: .url(#URL("https://www.google.com"))
            ),
        ]
    }

    var body: some View {
        NavigationStack {
            // ScrollView {
            if document != nil {
                CustomFieldEditView(document: Binding($document)!, store: store)
            }
            // }
        }
        .task {
            do {
                let repository = store.repository as! TransientRepository
                await repository.addUser(
                    User(id: 1, isSuperUser: false, username: "user", groups: [1]))
                try? await repository.login(userId: 1)
                for field in customFields {
                    _ = try await repository.add(customField: field)
                }
                try await store.fetchAll()
                try await store.repository.create(
                    document: ProtoDocument(title: "blubb"),
                    file: #URL("http://example.com"), filename: "blubb.pdf"
                )
                var document = try await store.repository.documents(filter: .default).fetch(
                    limit: 100_000
                ).first { $0.title == "blubb" }

                document?.customFields = instances.rawEntries

                self.document = document
                // print(document!)
            } catch { print(error) }
        }
    }
}

#Preview("Fully equipped") {
    @Previewable
    @StateObject var store = DocumentStore(repository: TransientRepository())
    @Previewable
    @StateObject var errorController = ErrorController()

    return PreviewHelper()
        .environmentObject(store)
        .environmentObject(errorController)
        .environment(\.locale, .init(identifier: "en_US"))
}
