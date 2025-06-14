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

private struct FieldLabeledView<Content: View>: View {
    let instance: CustomFieldInstance
    var content: () -> Content

    init(_ instance: CustomFieldInstance, content: @escaping () -> Content) {
        self.instance = instance
        self.content = content
    }

    var body: some View {
        Section {
            content()
        }
    }
}

private struct StringView: View {
    @Binding var instance: CustomFieldInstance

    @State private var text: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .string(string) = instance.wrappedValue.value {
            _text = State(initialValue: string)
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $text)
        }
        .onChange(of: text) {
            instance.value = .string(text)
        }
    }
}

private struct FloatView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .float(float) = instance.wrappedValue.value {
            _value = State(initialValue: String(float))
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $value)
                .keyboardType(.decimalPad)
        }
        .onChange(of: value) { old, new in
            guard let val = Double(String(new)) else {
                value = old // Revert to old value if invalid
                return
            }
            instance.value = .float(val)
        }
    }
}

private struct BooleanView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: Bool = false

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .boolean(bool) = instance.wrappedValue.value {
            _value = State(initialValue: bool)
        }
    }

    var body: some View {
        Toggle(isOn: $value) {
            Text(instance.field.name)
        }
        .onChange(of: value) { _, new in
            instance.value = .boolean(new)
        }
    }
}

private struct IntegerView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .integer(integer) = instance.wrappedValue.value {
            _value = State(initialValue: String(integer))
        }
    }

    var body: some View {
        Section(instance.field.name) {
            TextField(instance.field.name, text: $value)
                .keyboardType(.numberPad)
        }
        .onChange(of: value) { old, new in
            guard let val = Int(String(new)) else {
                value = old // Revert to old value if invalid
                return
            }
            instance.value = .integer(val)
        }
    }
}

private struct DateView: View {
    @Binding var instance: CustomFieldInstance

    @State private var value: Date = .init()

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .date(date) = instance.wrappedValue.value {
            _value = State(initialValue: date)
        }
    }

    var body: some View {
        DatePicker(selection: $value, displayedComponents: .date) {
            Text(instance.field.name)
        }
        .onChange(of: value) { _, new in
            instance.value = .date(new)
        }
    }
}

private struct MonetaryView: View {
    @Binding var instance: CustomFieldInstance

    @State private var amount: Decimal = 0.0
    @State private var amountString: String = ""

    @State private var currency: String = ""

    @Environment(\.locale) private var locale

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
    }

    private var defaultCurrency: String {
        instance.field.extraData.defaultCurrency ?? Locale.current.currency?.identifier ?? ""
    }

    var body: some View {
        Section(instance.field.name) {
            HStack {
                if case let .monetary(currency, amount) = instance.value {
                    Text(amount, format: .currency(code: currency))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(.default, value: instance.value)
                        .contentTransition(.numericText())
                }

                TextField(defaultCurrency, text: $currency)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .fixedSize()

                TextField("Amount", text: $amountString)
                    .keyboardType(.decimalPad)
            }
        }
        .onChange(of: amountString) { old, new in
            guard let val = Decimal(string: new, locale: locale) else {
                amountString = old // Revert to old value if invalid
                return
            }
            amount = val
            instance.value = .monetary(currency: currency, amount: val)
        }

        .onChange(of: currency) { old, new in
            // check if is valid currency code
            let ex = /^[A-Z]*$/
            if new.wholeMatch(of: ex) == nil {
                currency = old // Revert to old value if invalid
                return
            }

            currency = new

            var setCurrency = new
            if setCurrency.isEmpty {
                setCurrency = defaultCurrency
            }

            if new.count == 0 || new.count == 3 {
                instance.value = .monetary(currency: setCurrency, amount: amount)
            }
        }

        .task {
            if case let .monetary(currency, amount) = instance.value {
                self.amount = amount
                amountString = amount.formatted(.number.locale(
                    locale
                )
                .grouping(.never)
                .decimalSeparator(strategy: .always)
                .precision(.fractionLength(2)))
                self.currency = currency
            }
        }
    }
}

struct UrlView: View {
    @Binding var instance: CustomFieldInstance

    @State private var url: String = ""

    init(instance: Binding<CustomFieldInstance>) {
        _instance = instance
        if case let .url(u) = instance.wrappedValue.value {
            _url = State(initialValue: u.absoluteString)
        }
    }

    private func valid(urlString: String) -> URL? {
        guard let u = URL(string: urlString), u.scheme != nil, u.host != nil else {
            return nil
        }
        return u
    }

    var body: some View {
        Section(instance.field.name) {
            if case let .url(u) = instance.value {
                HStack {
                    Link(u.absoluteString, destination: u)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if valid(urlString: url) != nil {
                        Image(systemName: "escape")
                            .foregroundStyle(.tint)
                            .accessibilityLabel(.localizable(.open))
                    } else {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .accessibilityLabel(.login(.errorUrlInvalid))
                    }
                }
            }

            TextField(instance.field.name, text: $url)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
        }

        .onChange(of: url) { _, new in
            guard let validUrl = valid(urlString: new) else {
                return
            }

            instance.value = .url(validUrl)
        }
    }
}

struct CustomFieldEditView: View {
    // @State private var viewModel: CustomFieldEditViewModel
    @Binding var document: Document
    @State private var customFields: [CustomFieldInstance] = []

    @EnvironmentObject var store: DocumentStore
    @Environment(\.locale) private var locale

    init(document: Binding<Document>, store _: DocumentStore) {
        _document = document
        // self.store = store
        // self._customFields = State(initialValue: [CustomFieldInstance].fromRawEntries(self.document.customFields.values, customFields: [:]))
        // self._viewModel = State(initialValue: CustomFieldEditViewModel(document: document))
    }

    @ViewBuilder
    private func fieldView(field: Binding<CustomFieldInstance>) throws -> some View {
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
        default:
            Section {
                Text(String(describing: field.wrappedValue.field.dataType))
            }
        }
    }

    var body: some View {
        Form {
            ForEach(0 ..< customFields.count, id: \.self) { index in
                let field = $customFields[index]
                try? fieldView(field: field)
                    .swipeActions {
                        Button("Delete") {}
                    }
            }

            Section {
                ForEach(customFields, id: \.self) { field in
                    VStack(alignment: .leading) {
                        Text(field.field.name).bold()
                        Text(String(describing: field.value))
                    }
                }
            }
        }
        .task {
            customFields = [CustomFieldInstance].fromRawEntries(
                document.customFields.values, customFields: store.customFields, locale: locale
            )
        }

        .onChange(of: customFields) {
//            print("customFields changed")
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
                field: customFields[5], value: .monetary(currency: "USD", amount: 1000.00)
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
        .environment(\.locale, .init(identifier: "en_US"))
}
