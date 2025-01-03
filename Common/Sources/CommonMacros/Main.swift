//
//  Main.swift
//  Common
//
//  Created by Paul Gessinger on 02.01.25.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CommonMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        URLMacro.self,
    ]
}
