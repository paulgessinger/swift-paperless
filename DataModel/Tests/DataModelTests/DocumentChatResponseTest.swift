//
//  DocumentChatResponseTest.swift
//  DataModel
//

import Foundation
import Testing

@testable import DataModel

@Suite
struct DocumentChatResponseTest {
  @Test("Plain text without a trailer is all content")
  func plainText() {
    let response = DocumentChatResponse(parsing: "The invoice total is 42 €.")
    #expect(response.content == "The invoice total is 42 €.")
    #expect(response.references.isEmpty)
  }

  @Test("The metadata trailer is split off into references")
  func trailer() {
    let raw =
      "Your bill is due on Friday."
      + "\n\n__PAPERLESS_CHAT_METADATA__"
      + #"{"references":[{"id":12,"title":"Electricity bill"},{"id":7,"title":"Contract"}]}"#
    let response = DocumentChatResponse(parsing: raw)
    #expect(response.content == "Your bill is due on Friday.")
    #expect(
      response.references == [
        DocumentChatReference(id: 12, title: "Electricity bill"),
        DocumentChatReference(id: 7, title: "Contract"),
      ])
  }

  @Test("A trailer whose JSON is still incomplete yields no references yet")
  func partialTrailer() {
    let raw = "Answer\n\n__PAPERLESS_CHAT_METADATA__{\"references\":[{\"id\":1"
    let response = DocumentChatResponse(parsing: raw)
    #expect(response.content == "Answer")
    #expect(response.references.isEmpty)
  }

  @Test(
    "A partially received delimiter is held back from the content",
    arguments: ["\n", "\n\n", "\n\n__PAPER", "\n\n__PAPERLESS_CHAT_METADATA_"])
  func partialDelimiter(suffix: String) {
    let response = DocumentChatResponse(parsing: "Answer" + suffix)
    #expect(response.content == "Answer")
  }

  @Test("Text that merely resembles the delimiter is kept")
  func lookalike() {
    let response = DocumentChatResponse(parsing: "Answer\n\n__NOT_IT")
    #expect(response.content == "Answer\n\n__NOT_IT")
  }

  @Test("Empty input")
  func empty() {
    #expect(DocumentChatResponse(parsing: "") == DocumentChatResponse())
  }
}
