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
import os

extension CustomFieldUnknownValue: DisplayableError {
  var message: String {
    String(localized: .customFields(.unknownValueError))
  }

  var details: String? {
    String(localized: .customFields(.unknownValueEncode))
  }
}

private struct InvalidFieldView: View {
  let instance: CustomFieldInstance
  let reason: CustomFieldValue.InvalidReason

  @State private var expanded = false

  var body: some View {
    let text: LocalizedStringResource =
      switch reason {
      case .invalidDate(let date):
        .customFields(.invalidDate(date))
      case .invalidURL(let url):
        .customFields(.invalidUrl(url))
      case .invalidMonetary(let value):
        .customFields(.invalidMonetary(value))
      case .invalidSelectOption(let option):
        .customFields(
          .invalidSelectOption(
            option, instance.field.extraData.selectOptions.map(\.label).joined(separator: ", ")))
      case .unknownValue:
        .customFields(.unknownValue)
      case .unknownDataType(let dataType):
        .customFields(.unknownDataType(dataType))
      case .typeMismatch(let dataType, let rawValue):
        .customFields(.typeMismatch(dataType.rawValue, String(describing: rawValue)))
      }

    VStack {
      HStack(alignment: .top) {
        Image(systemName: "exclamationmark.triangle.fill")
        VStack(alignment: .leading) {
          Text(instance.field.name)
            .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.top, 2)

      if expanded {
        Text(text)
          .transition(.opacity)
      }
    }
    .overlay(alignment: .topTrailing) {
      Button {
        expanded.toggle()
      } label: {
        Image(systemName: expanded ? "minus.circle" : "plus.circle")
      }
    }

    .foregroundStyle(.red)
    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
  }
}

private struct AddCustomFieldView: View {
  @Binding var customFields: [CustomFieldInstance]
  @EnvironmentObject var store: DocumentStore
  @EnvironmentObject var errorController: ErrorController

  @Environment(\.dismiss) private var dismiss
  @Environment(\.locale) private var locale

  @State private var searchText: String = ""

  private var availableFields: [CustomField] {
    store.customFields
      .map(\.value)
      .filter { field in
        !customFields.contains(where: {
          $0.field.id == field.id
        })
      }
      .filter { field in
        searchText.isEmpty || field.name.localizedCaseInsensitiveContains(searchText)
      }
      .sorted(by: { $0.name < $1.name })
  }

  var body: some View {
    NavigationStack {
      VStack {
        if !store.permissions.test(.view, for: .customField) {
          ContentUnavailableView(
            String(localized: .permissions(.noViewPermissionsDisplayTitle)),
            systemImage: "lock.fill",
            description: Text(.permissions(.noViewPermissionsCustomFields)))
        } else if availableFields.isEmpty {
          if !searchText.isEmpty {
            ContentUnavailableView.search
          } else {
            ContentUnavailableView(
              String(localized: .customFields(.noCustomFields)),
              systemImage: "tray.fill",
              description: Text(.customFields(.noCustomFieldsDescription)))
          }
        } else {
          List {
            ForEach(availableFields) { field in
              Button(field.name) {
                let instance = CustomFieldInstance.withDefaultValue(field: field, locale: locale)
                customFields.append(instance)
                dismiss()
              }
            }
          }
        }
      }
      .animation(.spring, value: availableFields)
      .searchable(
        text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
        prompt: .customFields(.searchPlaceholder)
      )

      .navigationTitle(.customFields(.addTitle))
      .navigationBarTitleDisplayMode(.inline)
    }

    .task {
      do {
        try await store.fetchAllCustomFields()
      } catch {
        //                Logger.shared.error("Error fetching custom fields: \(error, privacy: .public)")
        errorController.push(error: error)
      }
    }
  }
}

struct CustomFieldsEditView: View {
  @Binding var document: Document
  @State private var customFields: [CustomFieldInstance] = []

  @EnvironmentObject var store: DocumentStore
  @Environment(\.locale) private var locale
  @Environment(\.isEnabled) private var isEnabled

  @State private var showAddSheet = false
  @State private var showInvalidFields = false

  init(document: Binding<Document>) {
    _document = document
  }

  @ViewBuilder
  private func fieldView(index: Int, field: Binding<CustomFieldInstance>) throws -> some View {
    if case .invalid(let reason) = field.wrappedValue.value {
      InvalidFieldView(instance: field.wrappedValue, reason: reason)
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
          DocumentLinkView(instance: field, document: document)
        case .select:
          SelectView(instance: field)
        case .other(let dataType):
          // Theoretically this should never happen because we catch this above if the value is invalid
          InvalidFieldView(instance: field.wrappedValue, reason: .unknownDataType(dataType))
        }
      }
      .swipeActions {
        Button(.customFields(.delete), role: .destructive) {
          deleteField(index: index)
        }
        .disabled(!isEnabled)
      }
    }
  }

  @MainActor private func deleteField(index: Int) {
    Task {
      try? await Task.sleep(for: .seconds(0.5))  // Small delay to prevent jank
      customFields.remove(at: index)
    }
  }

  var body: some View {
    Form {
      if showInvalidFields {
        Section {
          VStack {
            ContentUnavailableView(
              .customFields(.invalidStateHeadline),
              systemImage: "exclamationmark.triangle.fill",
              description: Text(.customFields(.invalidStateDescription)))
          }
          .foregroundStyle(.red)
        }
      }

      if !store.permissions.test(.view, for: .customField) {
        ContentUnavailableView(
          .permissions(.noViewPermissionsDisplayTitle),
          systemImage: "lock.fill",
          description: Text(.permissions(.noViewPermissionsCustomFields))
        )
      } else {
        if document.customFields.isEmpty {
          ContentUnavailableView(
            .customFields(.noCustomFieldsInDocument),
            systemImage: "plus.square.dashed",
            description: Text(.customFields(.noCustomFieldsInDocumentDescription)))
        } else {
          ForEach(0..<customFields.count, id: \.self) { index in
            let field = $customFields[index]
            try? fieldView(index: index, field: field)
          }
        }
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
              let field =
                customFields.first { $0.field.id == entry.field }?.field.name ?? "Unknown Field"
              Text("#\(entry.field) (\(field))").bold()
              Text(String(describing: entry.value))
            }
          }
        }
      }
    }
    .animation(.default, value: document.customFields)

    .navigationTitle(.customFields(.title))
    .navigationBarTitleDisplayMode(.inline)

    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        Button {
          showAddSheet = true
        } label: {
          Image(systemName: "plus")
            .accessibilityLabel(.localizable(.add))
        }
        .disabled(!store.permissions.test(.view, for: .customField))
        .accessibilityAddTraits(.isButton)
      }
    }

    .sheet(isPresented: $showAddSheet) {
      AddCustomFieldView(customFields: $customFields)
    }

    .task {
      if customFields.isEmpty {
        customFields = [CustomFieldInstance].fromRawEntries(
          document.customFields.values, customFields: store.customFields, locale: locale
        )
      }
      showInvalidFields = customFields.hasInvalidValues
    }

    .onChange(of: customFields) {
      document.customFields = customFields.rawEntries
    }
  }
}

// - MARK: Previews

private let customFields = [
  CustomField(id: 1, name: "Custom float", dataType: .float),
  CustomField(id: 2, name: "Custom bool", dataType: .boolean),
  CustomField(id: 4, name: "Custom integer", dataType: .integer),
  CustomField(id: 7, name: "Custom string", dataType: .string),
  CustomField(id: 3, name: "Custom date", dataType: .date),
  CustomField(id: 6, name: "Local currency", dataType: .monetary),  // No default currency
  CustomField(
    id: 5, name: "Default USD", dataType: .monetary,
    extraData: .init(defaultCurrency: "USD")
  ),  // Default currency
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

private let instances = [
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

@MainActor
private func getDocument(store: DocumentStore) async throws -> Document? {
  let repository = store.repository as! TransientRepository
  repository.addUser(
    User(id: 1, isSuperUser: false, username: "user", groups: [1]))
  try? repository.login(userId: 1)
  for field in customFields {
    _ = try await repository.add(customField: field)
  }
  try await store.fetchAll()
  try await store.repository.create(
    document: ProtoDocument(title: "blubb"),
    file: #URL("http://example.com"), filename: "blubb.pdf"
  )
  return try await store.repository.documents(filter: .default).fetch(
    limit: 100_000
  ).first { $0.title == "blubb" }
}

#Preview("Fully equipped") {
  @Previewable
  @StateObject var store = DocumentStore(repository: TransientRepository())

  @Previewable
  @StateObject var errorController = ErrorController()

  @Previewable @State var document: Document?
  @Previewable @State var navPath = NavigationPath()

  NavigationStack {
    if document != nil {
      CustomFieldsEditView(document: Binding($document)!)
        .environmentObject(store)
        .environmentObject(errorController)
        .environment(\.locale, .init(identifier: "en_US"))
    }
  }
  .task {
    do {
      var thisDocument = try await getDocument(store: store)
      thisDocument?.customFields = instances.rawEntries
      document = thisDocument
    } catch { print(error) }
  }
}

#Preview("Empty") {
  @Previewable
  @StateObject var store = DocumentStore(repository: TransientRepository())

  @Previewable
  @StateObject var errorController = ErrorController()

  @Previewable @State var document: Document?
  @Previewable @State var navPath = NavigationPath()

  NavigationStack {
    if document != nil {
      CustomFieldsEditView(document: Binding($document)!)
        .environmentObject(store)
        .environmentObject(errorController)
        .environment(\.locale, .init(identifier: "en_US"))
    }

    Button("Toggle perms") {
      Task {
        let repository = store.repository as! TransientRepository
        repository.set(
          permissions: .full {
            $0.set(.view, to: !store.permissions.test(.view, for: .customField), for: .customField)
          })
        try await store.fetchAll()
      }
    }
  }
  .task {
    do {
      document = try await getDocument(store: store)

    } catch { print(error) }
  }
}

#Preview("Error display") {
  let errors: [CustomFieldValue.InvalidReason] = [
    .invalidDate("abc"),
    .invalidURL("abc"),
    .invalidMonetary("abc"),
    .invalidSelectOption("blubb"),
    .unknownValue,
    .unknownDataType("nopetype"),
    .typeMismatch(dataType: .other("no"), value: .string("yo")),
  ]

  let instance = CustomFieldInstance(
    field: CustomField(id: 1, name: "Test", dataType: .string), value: .invalid(.unknownValue))

  Form {
    ForEach(errors, id: \.self) { error in
      Section {
        InvalidFieldView(instance: instance, reason: error)
      }
    }
  }
}
