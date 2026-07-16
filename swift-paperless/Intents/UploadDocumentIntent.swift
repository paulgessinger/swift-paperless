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

  @Parameter(
    title: "Document",
    supportedTypeIdentifiers: ["public.image", "com.adobe.pdf"])
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
      let repository = try await PaperlessIntentRepository.repository(server: server)
      try await repository.create(
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
