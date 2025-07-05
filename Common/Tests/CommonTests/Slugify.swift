//
//  Slugify.swift
//  swift-paperlessTests
//
//  Created by Paul Gessinger on 01.05.25
//

import Foundation
import SwiftUI
import Testing

@testable import Common

@Test func testSlugify() throws {
  #expect("Some/Name".slugify() == "Some-Name")
  #expect("SomeüName".slugify() == "SomeuName")
  #expect("Some Name".slugify() == "Some Name")
  #expect("Some;Name".slugify() == "Some-Name")
  #expect("Hyvee 2025-03-30".slugify() == "Hyvee 2025-03-30")
}

@Test func testPathAssembly() throws {
  let file = URL(filePath: "file:///some/path/to/a/file/This Has Some not ök ø chars.pdf")!

  let ext = file.pathExtension
  let stem = file.deletingPathExtension().lastPathComponent
  #expect(stem == "This Has Some not ök ø chars")

  let slug = stem.slugify()
  #expect(slug == "This Has Some not ok - chars")

  let filename = ext.isEmpty ? stem : "\(slug).\(ext)"
  #expect(filename == "This Has Some not ok - chars.pdf")
}
