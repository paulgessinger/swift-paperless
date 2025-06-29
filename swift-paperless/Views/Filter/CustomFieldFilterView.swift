//
//  CustomFieldFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.06.25.
//

import DataModel
import Networking
import SwiftUI

private struct QueryView: View {
    var query: Query

    var body: some View {
        Form {
            Text(String(describing: query))
        }
    }
}

private struct ExpressionView: View {
    var expression: Expression

    var body: some View {
        Form {
            Section {
                Text(String(describing: expression))
            }

            Section {
                ForEach(expression.elements.indices, id: \.self) { index in
                    let value = expression.elements[index]
                    if value is Query {
                        QueryView(query: value as! Query)
                    }
                }
            }

            Button("Add query") {
                expression.elements.append(
                    Query(
                        customField: CustomField(id: 1, name: "Custom field", dataType: .string),
                        op: .exists,
                        argument: .string("example")
                    )
                )
            }

            Button("Add expression") {
                expression.elements.append(
                    Expression(logicalOperator: .or, elements: [])
                )
            }
        }
    }
}

protocol QueryElement {
    func view() -> AnyView
}

struct Expression: QueryElement {
    var logicalOperator: CustomFieldQuery.LogicalOperator
    var elements: [any QueryElement]

    init(logicalOperator: CustomFieldQuery.LogicalOperator, elements: [any QueryElement]) {
        self.logicalOperator = logicalOperator
        self.elements = elements
    }

    func view() -> AnyView {
        AnyView(Text("I am expression"))
    }
}

struct Query: QueryElement {
    var customField: CustomField
    var op: CustomFieldQuery.FieldOperator
    var argument: CustomFieldQuery.Argument

    init(customField: CustomField, op: CustomFieldQuery.FieldOperator, argument: CustomFieldQuery.Argument) {
        self.customField = customField
        self.op = op
        self.argument = argument
    }

    func view() -> AnyView {
        AnyView(Text("I am query"))
    }
}

struct CustomFieldFilterView: View {
    @Binding var query: CustomFieldQuery

//    @State private var query: Expression?

    var body: some View {
        Form {
            Section {
                switch query {
                case .op:
                    NavigationLink {
                        ExpressionView(expression: Binding(get: { query }))
                    } label: {
                        Text("Edit expression")
                    }
                }
            }

            if query == nil {
                Button {
                    query = Expression(logicalOperator: .or, elements: [])
                } label: {
                    Text("Add expression")
                }
            }

            Section {
                Text(String(describing: query))
            }
        }

        .task {
//            switch query {
//            case .none:
//                // if it's none, we need to create
//            }
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

#Preview {
    @Previewable
    @StateObject var store = DocumentStore(repository: TransientRepository())

    @Previewable @State var filterState = FilterState.default

    NavigationStack {
        CustomFieldFilterView()
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
        } catch {}
    }
    .environmentObject(store)
}
