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

// @Observable
// private class CustomFieldEditViewModel {
//     @ObservationIgnored
//     @Binding var document: Document

//     init(document: Binding<Document>) {
//         self._document = document
//     }
// }

private struct StringView: View {
    @Binding var value: CustomFieldInstance

    @State private var text: String = ""

    init(value: Binding<CustomFieldInstance>) {
        _value = value
        if case let .string(string) = value.wrappedValue.value {
            _text = State(initialValue: string)
        }
    }

    var body: some View {
        if value.field.dataType != .string {
            Text("ERROR")
        } else {
            LabeledContent {
                TextField("String", text: $text)
            } label: {
                Text(value.field.name)
            }
            .onChange(of: text) {
                value.value = .string(text)
            }
        }
    }
}

struct CustomFieldEditView: View {
    // @State private var viewModel: CustomFieldEditViewModel
    @Binding var document: Document
    @State private var customFields: [CustomFieldInstance] = []

    @EnvironmentObject var store: DocumentStore

    init(document: Binding<Document>, store _: DocumentStore) {
        _document = document
        // self.store = store
        // self._customFields = State(initialValue: [CustomFieldInstance].fromRawEntries(self.document.customFields.values, customFields: [:]))
        // self._viewModel = State(initialValue: CustomFieldEditViewModel(document: document))
    }

    private func fieldView(field: Binding<CustomFieldInstance>) throws -> some View {
        VStack {
            switch field.wrappedValue.field.dataType {
            case .string:
                StringView(value: field)
            default:
                Text(String(describing: field.wrappedValue.field.dataType))
            }
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(0 ..< customFields.count, id: \.self) { index in
                    let field = $customFields[index]
                    try? fieldView(field: field)
                }
            }

            ForEach(customFields, id: \.self) { field in
                VStack(alignment: .leading) {
                    Text(field.field.name).bold()
                    Text(String(describing: field.value))
                }
            }
        }
        .task {
            customFields = [CustomFieldInstance].fromRawEntries(
                document.customFields.values, customFields: store.customFields
            )
        }

        .onChange(of: customFields) {
            print("customFields changed")
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
        ]

        instances = [
            CustomFieldInstance(field: customFields[0], value: .float(123.45))!,
            CustomFieldInstance(field: customFields[1], value: .boolean(true))!,
            CustomFieldInstance(field: customFields[2], value: .integer(123))!,
            CustomFieldInstance(field: customFields[3], value: .string("Hello"))!,
            CustomFieldInstance(field: customFields[4], value: .date(Date()))!,
            CustomFieldInstance(
                field: customFields[5], value: .monetary(currency: "EUR", amount: 1000.00)
            )!,
            CustomFieldInstance(
                field: customFields[6], value: .monetary(currency: "CHF", amount: 1000.00)
            )!,
            CustomFieldInstance(
                field: customFields[7], value: .url(#URL("https://www.google.com"))
            )!,
            CustomFieldInstance(field: customFields[8], value: .documentLink([123]))!,
            CustomFieldInstance(
                field: customFields[9], value: .select(.init(id: "bb", label: "Option B"))
            )!,
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
}
