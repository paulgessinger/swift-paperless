//
//  SettingMacro.swift
//  Common
//
//  Created by Paul Gessinger on 26.07.26.
//

import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public enum SettingMacroError: DiagnosticMessage, Error {
  case notAProperty
  case noKey

  public var message: String {
    switch self {
    case .notAProperty:
      "@Setting can only be applied to a variable declaration"
    case .noKey:
      "@Setting needs the SettingKey to read and write, e.g. @Setting(.documentDeleteConfirmation)"
    }
  }

  public var diagnosticID: MessageID {
    switch self {
    case .notAProperty:
      MessageID(domain: "Common", id: "settingNotAProperty")
    case .noKey:
      MessageID(domain: "Common", id: "settingNoKey")
    }
  }

  public var severity: DiagnosticSeverity { .error }
}

/// Expands a property into a computed one over `store`, reporting reads and
/// writes to the observation registrar.
public enum SettingMacro: AccessorMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingAccessorsOf declaration: some DeclSyntaxProtocol,
    in _: some MacroExpansionContext
  ) throws(SettingMacroError) -> [AccessorDeclSyntax] {
    guard let binding = declaration.as(VariableDeclSyntax.self)?.bindings.first,
      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier
    else {
      throw .notAProperty
    }

    guard let key = node.arguments?.as(LabeledExprListSyntax.self)?.first?.expression else {
      throw .noKey
    }

    return [
      """
      get {
        access(keyPath: \\.\(name))
        return store[\(key)]
      }
      """,
      """
      set {
        withMutation(keyPath: \\.\(name)) {
          store[\(key)] = newValue
        }
      }
      """,
    ]
  }
}
