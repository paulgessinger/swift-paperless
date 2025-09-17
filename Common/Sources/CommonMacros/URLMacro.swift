import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public enum URLError: DiagnosticMessage, Error {
  case noLiteral
  case malformed(_ arg: String)

  public var message: String {
    switch self {
    case .noLiteral:
      "Not a static string literal"
    case .malformed(let arg):
      "Malformed URL: \"\(arg)\""
    }
  }

  //    public var description: String { message }

  public var diagnosticID: MessageID {
    switch self {
    case .noLiteral:
      MessageID(domain: "Common", id: "noLiteral")
    case .malformed:
      MessageID(domain: "Common", id: "malformed")
    }
  }

  public var severity: DiagnosticSeverity { .error }
}

public enum URLMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in _: some MacroExpansionContext
  ) throws(URLError) -> ExprSyntax {
    guard let argument = node.arguments.first?.expression,
      let segments = argument.as(StringLiteralExprSyntax.self)?.segments,
      segments.count == 1,
      case .stringSegment(let literalSegment)? = segments.first
    else {
      throw .noLiteral
    }

    guard URL(string: literalSegment.content.text) != nil else {
      throw .malformed(literalSegment.content.text)
    }

    return "URL(string: \(argument))!"
  }
}
