//
//  UploadDocumentIntent.swift
//  swift-paperless
//

import AppIntents
import AppShared
import DataModel
import Foundation

struct UploadDocumentIntent: AppIntent {
  // Metadata strings are spelled out as literal resources rather than going
  // through the generated `.intents(…)` accessors below. `appintentsmetadataprocessor`
  // resolves them at build time from the source text, so the key, table and
  // bundle all have to be literal — an accessor is a function call returning a
  // struct, and there is nothing for the extractor to read. Same catalog either
  // way; only the spelling differs.
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
  //
  // `.connectToPreviousIntentResult` marks this as the action's input, so
  // dropping the action after "Get Contents of Folder" or "Take Photo" wires
  // that result into the field directly. It is the parameter for it: the one
  // thing an upload cannot run without, and the only one a previous action
  // plausibly produces.
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

  // The `& ProvidesDialog` is load-bearing. AppIntents decides what a run may
  // hand back from the *declared* return type, not the concrete one, so the
  // conformance that `.result(dialog:)`'s container carries has to be spelled
  // out here to count. Behind a bare `some IntentResult` the framework discards
  // the dialog and logs "Did not declare ProvidesDialog but provided one" —
  // a failure mode in which the upload succeeds and only the confirmation
  // quietly goes missing.
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
      // Uploads, and nothing else. Keeping this server's caches current belongs
      // to the app's foreground sync and the `SyncEngine`'s sweeps, which weigh
      // the per-server `syncOverCellular` gate and the 300 s reconcile throttle
      // — budgets an automation firing once per file would walk straight
      // through. An upload has nothing to contribute to those caches in any
      // case: the server consumes it asynchronously, so the new document does
      // not exist yet by the time a sync started here would look for it.
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
