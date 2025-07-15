//
//  CustomFieldFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.06.25.
//

import CasePaths
import DataModel
import Networking
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

    var body: some View {
        Form {
            Section {
                ForEach(op.args.indices, id: \.self) { index in
                    Group {
                        let arg = $op.args[index]
                        if let op = arg.op {
                            NavigationLink {
                                OpView(op: op)
                            } label: {
                                Text(arg.wrappedValue.rawValue)
                            }
                        }
                        if let expr = arg.expr {
                            NavigationLink {
                                ExprView(expr: expr)
                            } label: {
                                Text(arg.wrappedValue.rawValue)
                            }
                        }
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
                Picker("Operator", selection: $op.op) {
                    Text("And").tag(CustomFieldQuery.LogicalOperator.and)
                    Text("Or").tag(CustomFieldQuery.LogicalOperator.or)
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

private struct ExprView: View {
    @Binding var expr: ExprContent

    @State private var field: CustomField?

    @EnvironmentObject private var store: DocumentStore

    private var fields: [CustomField] {
        Array(store.customFields.values
            .sorted(by: {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            })
        )
    }

    private typealias FieldOperator = CustomFieldQuery.FieldOperator

    private var eligibleOperators: [FieldOperator] {
        var result: [FieldOperator] = [.exists, .isnull]

        switch field?.dataType {
        case .select:
            result.append(contentsOf: [.exact, .in])
        default: break
        }

        return result
    }

    var body: some View {
        Form {
            Picker("Field", selection: $expr.id) {
                ForEach(fields, id: \.id) { field in
                    Text(field.name).tag(field.id)
                }
            }

            Picker("Operator", selection: $expr.op) {
                ForEach(eligibleOperators, id: \.self) { op in
                    Text(op.localizedName).tag(op)
                }
            }

//            Text("Field: \(field?.name ?? "Unknown")")
            Text(CustomFieldQuery.expr(expr).rawValue)
        }
        .task {
            field = store.customFields[expr.id]
        }

        .onChange(of: expr.id) {
            field = store.customFields[expr.id]
        }
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
        ExprView(expr: $expr)
    }
}
