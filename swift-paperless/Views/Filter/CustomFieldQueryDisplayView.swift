//
//  CustomFieldQueryDisplayView.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 24.08.25.
//

import DataModel
import Networking
import SwiftUI

private struct BracketShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()

    path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))

    return path
  }
}

private struct OpView: View {
  let op: CustomFieldQuery.LogicalOperator
  let args: [CustomFieldQuery]

  @ScaledMetric(relativeTo: .body)
  private var labelSize = 25

  init(op: OpContent) {
    self.op = op.op
    args = op.args
  }

  var body: some View {
    HStack {
      Text("\(op.localizedName)")
        .fixedSize()
        .frame(width: labelSize)
        .rotationEffect(.degrees(-90))
      BracketShape()
        .stroke(lineWidth: 2)
        .frame(width: 5)

      VStack(alignment: .leading) {
        if !args.isEmpty {
          ForEach(args.indices, id: \.self) { idx in
            CustomFieldQueryDisplayView(query: args[idx])
          }
        } else {
          Text(.localizable(.none))
            .italic()
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 3)
  }
}

private struct ExprView: View {
  let fieldId: UInt
  let op: CustomFieldQuery.FieldOperator
  let arg: CustomFieldQuery.Argument

  @Environment(\.getCustomFieldById) private var getCustomFieldById

  @Environment(\.colorScheme) private var colorScheme

  init(expr: ExprContent) {
    fieldId = expr.id
    op = expr.op
    arg = expr.arg
  }

  @ViewBuilder
  private var background: some View {
    let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)

    shape
      .fill(
        Color(.tertiarySystemFill)
      )
  }

  var body: some View {
    HStack {
      Group {
        if let field = getCustomFieldById(fieldId) {
          Text(field.name)
        } else {
          Text(.customFields(.unknownCustomField(fieldId)))
        }
      }
      .bold()

      Text(op.shortDisplay)
        .padding(.horizontal, 5)
        .background(background)
      Text("`\(arg.display)`")
    }
  }
}

extension EnvironmentValues {
  @Entry fileprivate var getCustomFieldById: (UInt) -> CustomField? = {
    _ in nil
  }
}

struct CustomFieldQueryDisplayView: View {
  let query: CustomFieldQuery
  @EnvironmentObject private var store: DocumentStore

  init(query: CustomFieldQuery) {
    self.query = query
  }

  init(op: OpContent) {
    query = CustomFieldQuery.op(op)
  }

  init(expr: ExprContent) {
    query = CustomFieldQuery.expr(expr)
  }

  private func customField(_ id: UInt) -> CustomField? {
    store.customFields[id]
  }

  var body: some View {
    Group {
      switch query {
      case .op(let op):
        OpView(op: op)
      case .expr(let expr):
        ExprView(expr: expr)
      case .any:
        Text(.customFields(.anyCustomFieldQuery))
      }
    }
    .environment(\.getCustomFieldById, customField)
  }
}

private func makeQuery() -> CustomFieldQuery {
  let json = """
    ["OR", [
        [4,"gt",6],
        [2,"exists","false"],
        ["AND", [
            [9,"contains",[1]],
            [10,"exact","bb"],
            ["OR", [
                [5,"gte",19.8]
            ]],
            ["AND", [
                [5,"gte",19.8]
            ]]
        ]]
    ]]
    """

  return CustomFieldQuery(rawValue: json)!
}

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
        Form {
          content()
        }
      }
    }
    .task {
      do {
        let repository = store.repository as! TransientRepository
        repository.addUser(
          User(id: 1, isSuperUser: false, username: "user", groups: [1]))
        try? repository.login(userId: 1)
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

#Preview("Op") {
  let query: CustomFieldQuery = makeQuery()

  PreviewHelper {
    CustomFieldQueryDisplayView(query: query)
  }
}

#Preview("Empty") {
  let query: CustomFieldQuery = .op(.and, [])

  PreviewHelper {
    CustomFieldQueryDisplayView(query: query)
  }
}

#Preview("Expr") {
  let query = CustomFieldQuery(rawValue: "[9,\"contains\",[1]]")!

  PreviewHelper {
    CustomFieldQueryDisplayView(query: query)
  }
}

#Preview("Any") {
  let query = CustomFieldQuery.any

  PreviewHelper {
    CustomFieldQueryDisplayView(query: query)
  }
}
