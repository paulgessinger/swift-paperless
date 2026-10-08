//
//  UploadDocumentIntent.swift
//  swift-paperless
//

import AppIntents
import AppShared
import AppViews
import DataModel
import Foundation

struct UploadDocumentIntent: AppIntent {
  // Metadata strings are literal resources, not the generated `.intents(…)`
  // accessors: `appintentsmetadataprocessor` reads them from the source text.
  static let title = LocalizedStringResource("uploadDocumentIntentTitle", table: "Intents")
  static let description = IntentDescription(
    LocalizedStringResource("uploadDocumentIntentDescription", table: "Intents"))
  static let openAppWhenRun = false

  static var parameterSummary: some ParameterSummary {
    Summary("Upload \(\.$document) to \(\.$server)") {
      \.$title
      \.$documentType
      \.$correspondent
      \.$tags
    }
  }

  // `public.data` is every file with byte-stream contents but no directories.
  // Shortcuts applies this list while the shortcut is edited, before a file's
  // real type is known, so anything narrower would reject files handed over by
  // other actions. The server rejects formats it cannot parse.
  //
  // `.connectToPreviousIntentResult` wires the previous action's result into
  // this field, the one parameter an upload cannot run without.
  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentDocumentParameter", table: "Intents"),
    supportedTypeIdentifiers: ["public.data"],
    inputConnectionBehavior: .connectToPreviousIntentResult)
  var document: IntentFile

  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentServerParameter", table: "Intents"))
  var server: PaperlessServerEntity

  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentTitleParameter", table: "Intents"))
  var title: String?

  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentDocumentTypeParameter", table: "Intents"))
  var documentType: PaperlessDocumentTypeEntity?

  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentCorrespondentParameter", table: "Intents"))
  var correspondent: PaperlessCorrespondentEntity?

  @Parameter(
    title: LocalizedStringResource("uploadDocumentIntentTagsParameter", table: "Intents"))
  var tags: [PaperlessTagEntity]?

  init() {}

  // The `& ProvidesDialog` is needed: AppIntents reads the declared return type,
  // and behind a bare `some IntentResult` the dialog is discarded.
  func perform() async throws -> some IntentResult & ProvidesDialog {
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
      // Uploads only; cache upkeep belongs to the app's sync and `SyncEngine`,
      // which respect the `syncOverCellular` gate and the reconcile throttle.
      try await store.repository.create(
        document: document,
        file: uploadFile.url,
        filename: uploadFile.filename)
    } catch let error as PaperlessIntentError {
      throw error
    } catch {
      throw PaperlessIntentError.uploadFailed(error.localizedDescription)
    }

    return .result(dialog: IntentDialog(.intents(.uploadDocumentIntentSuccess)))
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
