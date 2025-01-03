//
//  Common.swift
//  Common
//
//  Created by Paul Gessinger on 31.12.24.
//
import Foundation

@freestanding(expression)
public macro URL<S: ExpressibleByStringLiteral>() -> URL = #externalMacro(module: "CommonMacros", type: "URLMacro")
