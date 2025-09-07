//
//  CustomFieldFilterView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 28.06.25.
//

import CasePaths
import Common
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
                CustomFieldQueryDisplayView(op: op.wrappedValue)
                    .listRowInsets(EdgeInsets())
            }
        }
        if let expr = arg.expr, let field = store.customFields[expr.wrappedValue.id] {
            NavigationLink {
                ExprView(field: field, expr: expr)
            } label: {
                CustomFieldQueryDisplayView(expr: expr.wrappedValue)
                    .listRowInsets(EdgeInsets())
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
                            Label(.localizable(.delete), systemImage: "trash")
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
                Button {
                    op.args.append(.op(.or, []))
                } label: {
                    Label(localized: .customFields(.addOpButtonLabel), systemImage: "curlybraces.square.fill")
                }

                Button {
                    if let defaultField {
                        op.args.append(.expr(defaultField.id, .exists, .string("true")))
                    }
                } label: {
                    Label(localized: .customFields(.addExprButtonLabel), systemImage: "plus.square.fill")
                }
                .disabled(defaultField == nil)

            } footer: {
                if defaultField == nil {
                    Text(.customFields(.noCustomFields))
                }
            }

            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
        .animation(.spring, value: op)
    }
}

extension CustomFieldQuery.FieldOperator {
    static func eligibleOperators(for dataType: CustomField.DataType) -> [Self] {
        let extra: [Self] = switch dataType {
        case .select: [.exact, .in]
        case .boolean: [.exact]
        case .string, .url: [.exact, .icontains]
        case .monetary: [.exact, .icontains, .gt, .gte, .lt, .lte]
        case .float, .integer: [.exact, .gt, .gte, .lt, .lte]
        case .date: [.exact, .gte, .lte]
        case .documentLink: [.contains]
        default: []
        }

        var result: [Self] = [.exists, .isnull]
        result.append(contentsOf: extra)

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
            switch value {
            case let .string(val):
                stringValue = val
            case let .number(val):
                stringValue = String(val)
                value = .string(stringValue)
            case let .integer(val):
                stringValue = String(val)
                value = .string(stringValue)
            case .array:
                // nothing we can do here
                stringValue = ""
                value = .string("")
            }
        }

        .onChange(of: stringValue) {
            value = .string(stringValue)
        }
    }
}

private struct FloatArgView: View {
    @Binding var value: CustomFieldQuery.Argument

    @State private var stringValue: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(.customFields(.queryArgumentLabel))
                .font(.caption)

            TextField(String(localized: .customFields(.queryArgumentLabel)),
                      text: $stringValue)
                .keyboardType(.decimalPad)
        }

        .task {
            if case let .number(val) = value {
                stringValue = String(val)
            } else if case let .string(val) = value, let doubleVal = Double(val) {
                stringValue = String(doubleVal)
                value = .number(doubleVal) // Convert to number
            } else {
                stringValue = "0"
                value = .number(0.0) // Ensure we have a valid number
            }
        }

        .onChange(of: stringValue) { old, new in
            guard let val = Double(String(new)) else {
                stringValue = old // Revert to old value if invalid
                return
            }

            value = .number(val)
        }
    }
}

#Preview("Float") {
    @Previewable @State var expr = ExprContent(id: 1, op: .gte, arg: .number(1.2))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == expr.id }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}

private struct IntegerArgView: View {
    @Binding var value: CustomFieldQuery.Argument

    @State private var stringValue: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(.customFields(.queryArgumentLabel))
                .font(.caption)

            TextField(String(localized: .customFields(.queryArgumentLabel)),
                      text: $stringValue)
                .keyboardType(.decimalPad)
        }

        .task {
            if case let .integer(val) = value {
                stringValue = String(val)
            } else if case let .string(val) = value, let intVal = Int(val) {
                stringValue = String(intVal)
                value = .integer(intVal) // Convert to integer
            } else {
                stringValue = "0"
                value = .integer(0) // Ensure we have a valid number
            }
        }

        .onChange(of: stringValue) { old, new in
            guard let val = Int(String(new)) else {
                stringValue = old // Revert to old value if invalid
                return
            }

            value = .integer(val)
        }
    }
}

#Preview("Integer") {
    @Previewable @State var expr = ExprContent(id: 4, op: .gte, arg: .integer(2))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == expr.id }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}

private struct DocumentArgView: View {
    @Binding var value: CustomFieldQuery.Argument

    @State private var ids: [UInt] = []

    private func updateValue() {
        value = .array(ids.map { .integer(Int($0)) })
    }

    var body: some View {
        VStack(alignment: .leading) {
            DocumentSelectionView(title: String(localized: .customFields(.queryArgumentLabel)),
                                  documentIds: $ids)
        }

        .task {
            if case let .array(arr) = value {
                ids = arr.compactMap {
                    if case let .integer(id) = $0 {
                        return UInt(id)
                    }
                    return nil
                }
                // Rewrite the value so it's value once we switch to this data type
                updateValue()
            } else {
                value = .array([])
                ids = []
            }
        }

        .onChange(of: ids) {
            updateValue()
        }
    }
}

#Preview("Doc link") {
    @Previewable @State var expr = ExprContent(id: 9, op: .contains, arg: .array([
        .integer(1), .string("NOPE"), .integer(2),
    ]))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == expr.id }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}

private struct DateArgView: View {
    @Binding var value: CustomFieldQuery.Argument

    @State var date = Date.now

    private func updateValue() {
        value = .string(CustomFieldInstance.dateFormatter.string(from: date))
    }

    var body: some View {
        DatePicker(selection: $date, displayedComponents: .date) {
            Text(.customFields(.queryArgumentLabel))
        }

        .task {
            if case let .string(val) = value {
                if let date = CustomFieldInstance.dateFormatter.date(from: val) {
                    self.date = date
                } else {
                    date = .now
                }
            }
            updateValue()
        }

        .onChange(of: date) {
            updateValue()
        }
    }
}

#Preview("Date") {
    @Previewable @State var expr = ExprContent(id: 3, op: .exact, arg: .string("2025-10-09"))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == expr.id }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}

private struct SelectExactArgView: View {
    var field: CustomField

    @Binding var value: CustomFieldQuery.Argument

    @State private var selected: String = ""

    var body: some View {
        Picker(String(localized: .customFields(.queryArgumentLabel)), selection: $selected) {
            ForEach(field.extraData.selectOptions) { option in
                Text(option.label)
                    .tag(option.id)
            }
        }

        .task {
            if case let .string(val) = value, field.extraData.selectOptions.contains(where: { $0.id == val }) {
                selected = val
            } else {
                selected = field.extraData.selectOptions.first?.id ?? ""
                value = .string(selected)
            }
        }

        .onChange(of: selected) {
            value = .string(selected)
        }
    }
}

private struct MultiPicker<T, Content, Label>: View
    where Content: View, Label: View, T: CustomStringConvertible & Hashable
{
    var content: (T) -> Content
    var label: () -> Label

    let options: [T]
    @Binding var selection: [T]

    init(options: [T], selection: Binding<[T]>, @ViewBuilder content: @escaping (T) -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.options = options
        _selection = selection
        self.content = content
        self.label = label
    }

    private struct OptionPickerView: View {
        let options: [T]
        @Binding var selection: [T]
        var content: (T) -> Content

        private func toggle(_ option: T) {
            if selection.contains(option) {
                selection.removeAll(where: { $0 == option })
            } else {
                selection.append(option)
            }
        }

        var body: some View {
            List {
                ForEach(options, id: \.self) { option in
                    Button {
                        toggle(option)
                    }
                    label: {
                        HStack {
                            content(option)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if selection.contains(option) {
                                SwiftUI.Label(localized: .localizable(.selected),
                                              systemImage: "checkmark")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                }
            }
        }
    }

    var body: some View {
        NavigationLink {
            OptionPickerView(options: options,
                             selection: $selection,
                             content: content)
        } label: {
            LabeledContent {
                Text(selection.map(\.description).joined(separator: ", "))
            } label: {
                label()
            }
        }
    }
}

extension MultiPicker where Label == EmptyView {
    init(options: [T], selection: Binding<[T]>, @ViewBuilder content: @escaping (T) -> Content) {
        self.init(options: options, selection: selection, content: content, label: { EmptyView() })
    }
}

private struct SelectInArgView: View {
    var field: CustomField

    @Binding var value: CustomFieldQuery.Argument

    @State private var selected: [String] = []

    private func optionView(_ id: String) -> some View {
        let name = field.extraData.selectOptions.first(where: { $0.id == id })?.label ?? "???"
        return Text(name)
    }

    var body: some View {
        MultiPicker(options: field.extraData.selectOptions.map(\.id),
                    selection: $selected,
                    content: { option in optionView(option) },
                    label: {
                        Text(String(localized: .customFields(.queryArgumentLabel)))
                    })

                    .task {
                        switch value {
                        case let .string(val) where field.extraData.selectOptions.contains(where: { $0.id == val }):
                            selected = [val]

                        case let .array(arr):
                            selected = arr.compactMap {
                                if case let .string(id) = $0, field.extraData.selectOptions.contains(where: { $0.id == id }) {
                                    return id
                                }
                                return nil
                            }
                            value = .array(selected.map { .string($0) })

                        default:
                            selected = []
                            value = .array([])
                        }
                    }

                    .onChange(of: selected) {
                        value = .array(selected.map { .string($0) })
                    }
    }
}

#Preview("Select") {
    @Previewable @State var expr = ExprContent(id: 10, op: .in, arg: .array([.string("bb")]))

    PreviewHelper {
        if let field = customFields.first(where: { $0.id == expr.id }) {
            ExprView(field: field, expr: $expr)
        } else {
            Text("Field not found")
        }
    }
}

private struct ExprArgView: View {
    @Binding var op: CustomFieldQuery.FieldOperator
    @Binding var field: CustomField
    @Binding var value: CustomFieldQuery.Argument

    private func unknownView() -> some View {
        let debugStr = CustomFieldQuery.expr(field.id, op, value).rawValue

        return VStack {
            WarningView {
                if Bundle.main.appConfiguration == .AppStore {
                    // On AppStore version, just show basic info
                    Text(.customFields(.invalidOperatorForField))
                } else {
                    // In TestFlight, encourage users to help

                    VStack(alignment: .leading) {
                        Text("Operation *\(op.localizedName)* is not covered by UI")
                        Text("Expression is: `\(debugStr)`")
                        Text("Custom field type: `\(String(describing: field.dataType))`")
                    }
                }
            }

            if Bundle.main.appConfiguration != .AppStore {
                Divider()

                Text("This should be covered by the UI. **You're on TestFlight**: please send me feedback with the details:")

                Button("Copy details to clipboard!") {
                    let detailStr = """
                    Uncovered custom field query construct:
                    OP: \(String(describing: op))
                    Field: \(String(describing: field))
                    Argument: \(String(describing: value))
                    """
                    Pasteboard.general.string = detailStr
                    Logger.shared.warning("\(detailStr)")
                }
                .buttonStyle(.borderedProminent)
                .tint(.yellow)
            }
        }
    }

    var body: some View {
        switch op {
        case .exists, .isnull:
            ToggleArgView(value: $value)
        case .exact:
            switch field.dataType {
            case .boolean:
                ToggleArgView(value: $value)
            case .string, .url, .monetary:
                StringArgView(value: $value)
            case .float:
                FloatArgView(value: $value)
            case .integer:
                IntegerArgView(value: $value)
            case .date:
                DateArgView(value: $value)
            case .select:
                SelectExactArgView(field: field,
                                   value: $value)
            default: unknownView()
            }
        case .icontains:
            StringArgView(value: $value)
        case .gt, .gte, .lt, .lte:
            switch field.dataType {
            case .monetary, .float:
                FloatArgView(value: $value)
            case .integer:
                IntegerArgView(value: $value)
            case .date:
                DateArgView(value: $value)
            default: unknownView()
            }
        case .contains:
            switch field.dataType {
            case .documentLink:
                DocumentArgView(value: $value)
            default: unknownView()
            }
        case .in:
            switch field.dataType {
            case .select:
                SelectInArgView(field: field,
                                value: $value)

            default: unknownView()
            }
        }

        // DEBUG:
        // Text(String(describing: value))
    }
}

private struct WarningView<Content: View>: View {
    @ViewBuilder
    var content: () -> Content

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: "exclamationmark.triangle")

            content()
        }
        .foregroundStyle(.yellow)
        .bold()
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

                let eligible = FieldOperator.eligibleOperators(for: field.dataType)
                Picker(.customFields(.queryOperatorLabel), selection: $expr.op) {
                    ForEach(FieldOperator.allCases, id: \.self) { op in
                        Text(op.localizedName)
                            .tag(op)
                            .selectionDisabled(!eligible.contains(op))
                    }
                }
                if FieldOperator.eligibleOperators(for: field.dataType).contains(expr.op) {
                    ExprArgView(op: $expr.op, field: $field, value: $expr.arg)
                } else {
                    WarningView {
                        Text(.customFields(.invalidOperatorForField))
                    }
                }
            }

            // @TODO: Remove this!
            // DEBUG:
//            Section {
//                Text(CustomFieldQuery.expr(expr).rawValue)
//            }
        }

        .onChange(of: expr.id) { updateField(expr.id) }
    }
}

struct CustomFieldQueryEditView<Content: View>: View {
    @Binding var query: CustomFieldQuery

    let content: () -> Content

    init(query: Binding<CustomFieldQuery>, @ViewBuilder content: @escaping () -> Content) {
        _query = query
        self.content = content
    }

    var body: some View {
        Form {
            content()

            if query != .any {
                Section {
                    if let op = $query.op {
                        NavigationLink {
                            OpView(op: op)
                        } label: {
                            CustomFieldQueryDisplayView(query: query)
                                .listRowInsets(EdgeInsets())
                        }
                    }
                }

                Section {
                    Button {
                        query = .any
                    } label: {
                        Label(localized: .customFields(.clearCustomFieldFilterButtonLabel), systemImage: "xmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .foregroundColor(.red)
                }
            } else {
                Section {
                    ContentUnavailableView(.customFields(.anyCustomFieldQuery), systemImage: "line.3.horizontal.decrease.circle.fill")
                }

                Section {
                    Button {
                        query = .op(.or, [])
                    } label: {
                        Label(localized: .customFields(.addCustomFieldFilterButtonLabel), systemImage: "plus.circle.fill")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .animation(.spring, value: query)
    }
}

extension CustomFieldQueryEditView where Content == EmptyView {
    init(query: Binding<CustomFieldQuery>) {
        self.init(query: query, content: { EmptyView() })
    }
}

struct CustomFieldFilterView: View {
    @Binding private var outputQuery: CustomFieldQuery

    @State private var query: CustomFieldQuery

    private enum QueryState {
        case checking
        case error
        case valid
    }

    @State private var state = QueryState.valid

    @EnvironmentObject private var store: DocumentStore
    @Environment(\.dismiss) private var dismiss

    init(query: Binding<CustomFieldQuery>) {
        _outputQuery = query
        _query = State(initialValue: query.wrappedValue)
    }

    private func validate() async {
        Logger.shared.info("Validating custom field query: \(query.rawValue, privacy: .public)")

        guard query != .any else {
            Logger.shared.info("Query is .any, nothing to validate")
            outputQuery = query
            state = .valid
            return
        }

        let emptyDefaultQuery = CustomFieldQuery.op(.or, [])
        guard query != emptyDefaultQuery else {
            Logger.shared.info("Query is \(query.rawValue, privacy: .public), which is equivalent to .any, we'll apply that")
            outputQuery = .any
            state = .valid
            return
        }

        state = .checking
        try? await Task.sleep(for: .seconds(2))

        let filterState = FilterState.empty.with {
            $0.customField = query
        }

        guard store.permissions.test(.view, for: .document) else {
            Logger.shared.info("User does not have permission to view documents. Let them set filter without validation")
            outputQuery = query
            state = .valid
            return
        }

        do {
            Logger.shared.info("Requesting documents to validate custom field query")
            state = .checking
            _ = try await store.repository.documents(filter: filterState).fetch(limit: 1)
            Logger.shared.info("Documents received, setting filter")
            outputQuery = query
            state = .valid
        } catch {
            Logger.shared.error("Received error loading documents with filter, presenting error and not modifying actual filter state: \(error)")
            state = .error
        }
    }

    var body: some View {
        NavigationStack {
            CustomFieldQueryEditView(query: $query) {
                if state == .error {
                    HStack(alignment: .top) {
                        Image(systemName: "xmark.circle.fill")
                        Text(.customFields(.queryInvalidFilter))
                    }
                    .foregroundStyle(.red)
                }
            }
            .animation(.spring, value: state)

            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(.customFields(.title))

            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    switch state {
                    case .valid:
                        Button(.localizable(.done)) {
                            dismiss()
                        }
                    case .error:
                        Button(.customFields(.filterAbandonButtonLabel), role: .destructive) { dismiss()
                        }
                        .tint(.red)
                    case .checking:
                        ProgressView()
                    }
                }
            }
        }

        .interactiveDismissDisabled(state != .valid)

        .onChange(of: query) {
            Task {
                await validate()
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

    func addDocuments() async {
        let documents: [(String, String)] = [
            ("Invoice #123", "file1.pdf"),
            ("Receipt for groceries", "file2.pdf"),
            ("Tax document 2024", "file3.pdf"),
            ("Invoice #456", "file4.pdf"),
            ("Meeting notes", "file5.pdf"),
        ]

        for (title, filename) in documents {
            let protoDoc = ProtoDocument(
                title: title,
                asn: nil,
                documentType: nil,
                correspondent: nil,
                tags: [],
                created: .now,
                storagePath: nil
            )
            try? await store.repository.create(
                document: protoDoc, file: URL(string: "file:///\(filename)")!, filename: filename
            )
        }
    }

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
                await addDocuments()

                show = true
            } catch {}
        }
        .environmentObject(store)
    }
}

#Preview("Combined") {
    @Previewable @State var filterState = FilterState.default

    PreviewHelper {
        CustomFieldQueryEditView(query: $filterState.customField)
        Button("Print!") {
            print(filterState.customField.rawValue)
        }
    }
}

#Preview("FilterView") {
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

// @TODO: Add check by sending this to the server and see if it accepts it! Show big error if not!
