//
//  DocumentTypealias.swift
//  swift-paperless
//
//  SwiftUI in SDK 27 declares its own top-level `Document` type, which makes
//  unqualified `Document` ambiguous in files importing both SwiftUI and
//  DataModel. A same-module typealias wins unqualified lookup, so all uses in
//  this module keep resolving to the DataModel type.
//

import DataModel

public typealias Document = DataModel.Document
