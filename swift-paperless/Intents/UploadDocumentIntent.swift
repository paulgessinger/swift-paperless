//
//  UploadDocumentIntent.swift
//  swift-paperless
//

import AppIntents
import AppShared
import DataModel
import Foundation

struct UploadDocumentIntent: AppIntent {
  static let title: LocalizedStringResource = "Upload Document"
  static let description = IntentDescription("Uploads a document to a Paperless server.")
  static let openAppWhenRun = false

  static var parameterSummary: some ParameterSummary {
    Summary("Upload \(\.$document) to \(\.$server)") {
      \.$title
      \.$documentType
      \.$correspondent
      \.$tags
    }
  }

  // `public.data` is every file with byte-stream contents, and no directories —
  // which is why it, rather than the `public.item` default that folders also
  // conform to.
  //
  // The list is a compile-time constant in the AppIntents metadata, and
  // Shortcuts applies it *while the shortcut is being edited*, before any
  // file's real type is known. It therefore governs which variables the field
  // accepts, not which files the action can handle: a PDF handed over by "Get
  // Contents of Folder" is typed generically at edit time, so anything narrower
  // rejects it and iterating a folder becomes unexpressible.
  //
  // Which formats are genuinely consumable is the server's own configuration —
  // Tika and Gotenberg decide whether office documents are parseable at all —
  // so the server is the only authority, and it already rejects what it cannot
  // read. A list here could only be a guess, wrong in both directions depending
  // on the deployment.
  @Parameter(
    title: "Document",
    supportedTypeIdentifiers: ["public.data"])
  var document: IntentFile

  @Parameter(title: "Server")
  var server: PaperlessServerEntity

  @Parameter(title: "Title")
  var title: String?

  @Parameter(title: "Document Type")
  var documentType: PaperlessDocumentTypeEntity?

  @Parameter(title: "Correspondent")
  var correspondent: PaperlessCorrespondentEntity?

  @Parameter(title: "Tags")
  var tags: [PaperlessTagEntity]?

  init() {}

  func perform() async throws -> some IntentResult {
    let uploadFile = try PaperlessIntentUploadFile.materialize(document)
    defer { uploadFile.cleanup() }

    let document = ProtoDocument(
      title: title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      documentType: documentType?.documentType.id,
      correspondent: correspondent?.correspondent.id,
      tags: tags?.map(\.tag.id) ?? [],
      created: nil)

    do {
      let store = try await PaperlessIntentStore.store(server: server)
      // Opportunistic: refresh the element cache while the upload runs, so the
      // next shortcut run sees current tags/types/correspondents.
      Task { try? await store.sync(userInitiated: true) }
      try await store.repository.create(
        document: document,
        file: uploadFile.url,
        filename: uploadFile.filename)
    } catch let error as PaperlessIntentError {
      throw error
    } catch {
      throw PaperlessIntentError.uploadFailed(error.localizedDescription)
    }

    return .result(dialog: IntentDialog(.app(.uploadDocumentIntentSuccess)))
  }
}

struct PaperlessShortcutsProvider: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: UploadDocumentIntent(),
      phrases: [
        "Upload document to \(.applicationName)",
        "Upload a document to \(.applicationName)",
      ],
      shortTitle: "Upload Document",
      systemImageName: "doc.badge.arrow.up")
  }
}
