//
//  TaskModel+ResultKind.swift
//  DataModel
//
//  Coarse classification of `PaperlessTask.result`. The display layer switches
//  on this to render an appropriate (localized) message, keeping the branch
//  logic here — where it can be unit-tested without pulling in the iOS-only UI.
//

import Foundation

extension PaperlessTask {
  public enum ResultKind: Equatable, Sendable {
    /// No `result` text is available.
    case empty
    /// The task failed because the document is a duplicate. `fileName` is the
    /// task's `taskFileName` if set, otherwise `nil` (the display layer fills in
    /// a localized placeholder).
    case duplicate(fileName: String?)
    /// The task created a document.
    case created(documentId: UInt)
    /// A raw result string with no specialized handling.
    case raw(String)
  }

  public var resultKind: ResultKind {
    if duplicateDocumentId != nil {
      return .duplicate(fileName: taskFileName)
    }
    if let createdDocumentId {
      return .created(documentId: createdDocumentId)
    }
    guard let result else { return .empty }
    return .raw(result)
  }
}
