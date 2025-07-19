//
//  CustomFieldFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.06.25.
//

import CasePaths
import DataModel
import Networking
import os
import SwiftUI

private struct OpView: View {
    @Binding var op: OpContent

    @EnvironmentObject private var store: DocumentStore

    private var defaultField: CustomField? {
        store.customFields.values
            .sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }).first
    }

    @ViewBuilder
    private func rowView(for arg: Binding<CustomFieldQuery>) -> some View {
        if let op = arg.op {
            NavigationLink {
                OpView(op: op)
            } label: {
                Text(arg.wrappedValue.rawValue)
            }
        }
        if let expr = arg.expr, let field = store.customFields[expr.wrappedValue.id] {
            NavigationLink {
                ExprView(field: field, expr: expr)
            } label: {
                Text(arg.wrappedValue.rawValue)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                ForEach(op.args.indices, id: \.self) { index in
                    Group {
                        let arg = $op.args[index]
                        rowView(for: arg)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            op.args.remove(at: index)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Picker(String(localized: .customFields(.queryOperatorLabel)), selection: $op.op) {
                    Text(.customFields(.queryAnd)).tag(CustomFieldQuery.LogicalOperator.and)
                    Text(.customFields(.queryOr)).tag(CustomFieldQuery.LogicalOperator.or)
                }
                .pickerStyle(.segmented)
            } footer: {}

            Section {
                // If we don't have one, what's the point of adding an expr?
                if let defaultField {
                    Button("Add expr") {
                        op.args.append(.expr(defaultField.id, .exists, .string("true")))
                    }
                }

                Button("Add op") {
                    op.args.append(.op(.or, []))
                }
            }

            Section {
                Text(CustomFieldQuery.op(op).rawValue)
            }
        }
    }
}

extension CustomFieldQuery.FieldOperator {
    static func eligibleOperators(for dataType: CustomField.DataType) -> [Self] {
        var result: [Self] = [.exists, .isnull]

        switch dataType {
        case .select:
            result.append(contentsOf: [.exact, .in])
        case .boolean:
            result.append(contentsOf: [.exact])
        case .string, .url:
            result.append(contentsOf: [.exact, .icontains])
        case .monetary:
            result.append(contentsOf: [.exact, .icontains, .gt, .gte, .lt, .lte])
        default: break
        }

        return result
    }
}

private struct ToggleArgView: View {
    @Binding var value: CustomFieldQuery.Argument
    @State private var toggleValue: Bool = false

    init(value: Binding<CustomFieldQuery.Argument>) {
        _value = value
        if case let .string(val) = self.value {
            _toggleValue = State(initialValue: val != "false")
        } else {
            _toggleValue = State(initialValue: false)
        }
    }

    var body: some View {
        Toggle(isOn: $toggleValue) {
            Text(.customFields(.queryArgumentLabel))
        }

        .task {
            // To ensure the view matches the actual value, we need to reset the value here
            value = .string(toggleValue ? "true" : "false")
        }

        .onChange(of: toggleValue) {
            value = .string(toggleValue ? "true" : "false")
        }
    }
}

private struct StringArgView: View {
    @Binding var value: CustomFieldQuery.Argument

    @State private var stringValue: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(.customFields(.queryArgumentLabel))
                .font(.caption)

            TextField(String(localized: .customFields(.queryArgumentLabel)),
                      text: $stringValue)
        }

        .task {
            if case let .string(val) = value {
                stringValue = val
            }
        }

        .onChange(of: stringValue) {
            value = .string(stringValue)
        }
    }
}

private struct ExprArgView: View {
    @Binding var op: CustomFieldQuery.FieldOperator
    @Binding var field: CustomField
    @Binding var value: CustomFieldQuery.Argument

    var body: some View {
        switch op {
        case .exists, .isnull:
            ToggleArgView(value: $value)
        case .exact:
            switch field.dataType {
            case .boolean:
                ToggleArgView(value: $value)
            case .string, .date, .url, .monetary:
                StringArgView(value: $value)
            default:
                Text("Unknown EXACT")
            }
        case .icontains:
            StringArgView(value: $value)
        default:
            Text("Unknown")
        }

        Text(String(describing: value))
    }
}

private struct ExprView: View {
    @State var field: CustomField
    @Binding var expr: ExprContent

    @EnvironmentObject private var store: DocumentStore

    private var fields: [CustomField] {
        Array(store.customFields.values
            .sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        )
    }

    private typealias FieldOperator = CustomFieldQuery.FieldOperator

    private func updateField(_: UInt) {
        guard let field = store.customFields[expr.id] else {
            Logger.shared.error("Expression set to field with id \(expr.id, privacy: .public) which was not found")
            return
        }

        self.field = field
    }

    var body: some View {
        Form {
            Section {
                Picker(.customFields(.queryFieldLabel), selection: $expr.id) {
                    ForEach(fields, id: \.id) { field in
                        Text(field.name).tag(field.id)
                    }
                }

                Picker(.customFields(.queryOperatorLabel), selection: $expr.op) {
                    ForEach(FieldOperator.eligibleOperators(for: field.dataType), id: \.self) { op in
                        Text(op.localizedName).tag(op)
                    }
                }
                ExprArgView(op: $expr.op, field: $field, value: $expr.arg)
            }

            // @TODO: Remove this!
            Section {
                Text(CustomFieldQuery.expr(expr).rawValue)
            }
        }

        .onChange(of: expr.id) { updateField(expr.id) }
    }
}

struct CustomFieldFilterView: View {
    @Binding var query: CustomFieldQuery

    var body: some View {
        Form {
            Section {
                if let op = $query.op {
                    NavigationLink {
                        OpView(op: op)
                    } label: {
                        Text(query.rawValue)
                    }
                }
            }

            if query == .any {
                Button {
                    query = .op(.or, [])
                } label: {
                    Text("Add op")
                }
            }

            Section {
                Text(query.rawValue)
            }
        }
    }
}

private let customFields = [
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

private struct PreviewHelper<C: View>: View {
    @StateObject var store = DocumentStore(repository: TransientRepository())

    @State var show = false

    @ViewBuilder
    var content: () -> C

    var body: some View {
        NavigationStack {
            if show {
                content()
            }
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
                show = true
            } catch {}
        }
        .environmentObject(store)
    }
}

#Preview("Combined") {
    @Previewable @State var filterState = FilterState.default

    PreviewHelper {
        CustomFieldFilterView(query: $filterState.customField)
    }
}

#Preview("String") {
    @Previewable @State var expr = ExprContent(id: 7, op: .exists, arg: .string("test"))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == 7 }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}
