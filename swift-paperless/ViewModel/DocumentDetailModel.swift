//
//  DocumentDetailModel.swift
//  swift-paperless
//
//  Created by Paul Gessinger on 09.06.2024.
//

import AppShared
import AppViews
import Common
import DataModel
import Foundation
import Networking
import PDFKit
import SwiftUI
import os

/// What the preview shows for a downloaded file.
enum DocumentContent {
  case pdf(PDFDocument)
  /// A file PDFKit can't open, such as the original of a document without an
  /// archive version. QuickLook shows it from a link named after the server's
  /// filename, since it goes by the extension.
  case file(URL)
}

enum DocumentDownloadState: Equatable {
  case initial
  case loading
  /// `url` is the canonical stored file, which the share menu hands out.
  case loaded(url: URL, content: DocumentContent)
  case error

  // `.loaded` compares its payload, not just its case. SwiftUI uses the `==` of
  // a view's Equatable stored properties when it diffs, and
  // `IntegratedDocumentPreview` takes this value as a stored property — so
  // treating every `.loaded` as equal made swapping one document for another (a
  // re-download after a server-side version bump) invisible: the preview
  // subtree was never re-evaluated, and the new `PDFDocument` never reached
  // `PDFKitView`.
  //
  // It also silently disabled `.task(id: downloadState)` and
  // `.animation(value: downloadState)` across a `.loaded` → `.loaded` change.
  //
  // `PDFDocument` is a non-Equatable class, which is presumably why this was
  // hand-rolled; identity is the right comparison for it, since
  // `loadBackground` constructs a fresh instance per load.
  static func == (lhs: DocumentDownloadState, rhs: DocumentDownloadState) -> Bool {
    switch (lhs, rhs) {
    case (.initial, .initial), (.loading, .loading), (.error, .error):
      true
    case (.loaded(let lURL, .pdf(let lDocument)), .loaded(let rURL, .pdf(let rDocument))):
      lURL == rURL && lDocument === rDocument
    case (.loaded(let lURL, .file(let lLink)), .loaded(let rURL, .file(let rLink))):
      lURL == rURL && lLink == rLink
    default:
      false
    }
  }
}

/// Accumulates the errors thrown across one `DocumentDetailModel.load()` pass so
/// duplicates can be collapsed before they reach the caller's `onError`.
///
/// An unreachable server fails every request in the pass the same way, so
/// those should collapse to one entry, while genuinely different failures (a
/// permission error on a single endpoint, say) stay distinct and each still
/// show.
///
/// Connectivity failures arrive as `RequestError.connectivity`, which is equal
/// across endpoints for one outage and so compares by value like any other
/// `RequestError`. The transport failures `ApiRepository` still passes through
/// raw (SSL, redirects, ...) are bridged `URLError`s, whose `NSError.userInfo`
/// carries the failing URL and a per-request task id, so no two are ever equal
/// by value — not even two failures against the same endpoint. Those are
/// compared by code. Everything else (other `Equatable` errors) is compared by
/// value, which is what keeps distinct failures distinct.
@MainActor
private final class LoadErrorCollector {
  private(set) var distinct: [any Error] = []

  func add(_ error: any Error) {
    guard !distinct.contains(where: { Self.isDuplicate($0, error) }) else { return }
    distinct.append(error)
  }

  private static func isDuplicate(_ lhs: any Error, _ rhs: any Error) -> Bool {
    // Transport failures: same code means the same outage, whatever the URL.
    if let lhs = lhs as? URLError, let rhs = rhs as? URLError {
      return lhs.code == rhs.code
    }
    let lhsNS = lhs as NSError
    let rhsNS = rhs as NSError
    if lhsNS.domain == NSURLErrorDomain, rhsNS.domain == NSURLErrorDomain {
      return lhsNS.code == rhsNS.code
    }
    // Via `Any`: casting an `any Error` straight to `any Equatable` draws a
    // spurious "always succeeds" warning, though at runtime it correctly fails
    // for an error type that doesn't conform.
    guard let lhsEquatable = lhs as Any as? any Equatable,
      let rhsEquatable = rhs as Any as? any Equatable
    else {
      // Nothing better to go on for an error that can't be compared.
      return String(describing: lhs) == String(describing: rhs)
    }
    return isEqual(lhsEquatable, rhsEquatable)
  }

  /// Open the existentials to recover the concrete type and use its `==`.
  /// Errors of different types are never duplicates.
  private static func isEqual(_ lhs: any Equatable, _ rhs: any Equatable) -> Bool {
    func compare<T: Equatable>(_ lhs: T) -> Bool { (rhs as? T) == lhs }
    return compare(lhs)
  }
}

@MainActor
@Observable
class DocumentDetailModel {
  var download: DocumentDownloadState = .initial
  var downloadProgress: Double = 0.0
  /// A download is checking a stored preview that is already on screen.
  var isValidatingPreview = false

  enum OriginalDownloadState {
    case initial
    case loading
    case loaded(url: URL)
    case error
  }

  var originalDownload: OriginalDownloadState = .initial

  @ObservationIgnored
  var store: DocumentStore
  @ObservationIgnored
  var connection: Connection?

  var document: Document

  /// The first `loadDocument` has ended, either way. A successful one stored
  /// the document's text, usually without changing `document.modified`.
  var isDocumentLoaded = false

  // Not fully used by the edit model yet (I think we're loading suggestions twice right now)
  var suggestions = Suggestions()

  var metadata: Metadata?

  /// Kept apart from `document`, which is replaced by responses that don't
  /// carry duplicates. Only a detail fetch from the server changes this.
  var duplicates: [DocumentDuplicate] = []

  /// The in-flight load, owned by the model rather than by whichever view task
  /// happened to start it. See `startLoad(onError:)`.
  @ObservationIgnored
  private var loadTask: Task<Void, Never>?

  /// The preview on screen came from storage and no download has confirmed it
  /// yet, so it may be outdated.
  @ObservationIgnored
  private var previewNeedsValidation = false

  /// Identifies the file behind the preview on screen. A download that
  /// replaced the file returns the same URL, so the URL alone can't tell
  /// whether the preview needs reloading.
  @ObservationIgnored
  private var previewFileStamp: FileStamp?

  init(
    store: DocumentStore, connection: Connection?, document: Document
  ) {
    self.store = store
    self.connection = connection
    self.document = document
  }

  /// Permissions live in `ui_settings`, which the detail view never fetches on
  /// its own: without this, a permission change on the server doesn't reach the
  /// edit/delete affordances on this screen until the next launch or list
  /// refresh. Pulled in on refresh alongside the document itself. Fails soft
  /// like the other loads here — a stale permission set is better than a toast
  /// over the document.
  func refreshPermissions() async {
    do {
      try await store.fetchUISettings()
    } catch {
      Logger.shared.error("Error refreshing UI settings from document detail: \(error)")
    }
  }

  /// Run `load` in a task owned by the model rather than by the caller's.
  ///
  /// A load must not be a structured child of the task that starts it, because
  /// both of the view's entry points have a lifetime shorter than the work:
  /// `.refreshable`'s task belongs to the pull gesture, and SwiftUI ends it when
  /// the scroll view's content changes underneath it. A refresh that picks up a
  /// new document version does exactly that — `loadDocument` swaps in the new
  /// PDF, the preview inside the scroll view is replaced, the refresh session
  /// ends, and the still-running metadata/notes/suggestions legs are cancelled
  /// mid-flight. The refresh cancels itself, and the user gets a "cancelled"
  /// toast for a refresh that silently didn't finish.
  ///
  /// An unstructured `Task` doesn't inherit cancellation (only priority and
  /// actor isolation), so the legs survive the gesture ending. View *dismissal*
  /// is still a real cancellation boundary — the view calls `cancelLoad()` on
  /// disappear — so a load whose result nobody will see still stops promptly,
  /// rather than surfacing a toast over whatever screen came next.
  func startLoad(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    // Latest wins: a pull-to-refresh supersedes an on-appear load still running.
    loadTask?.cancel()
    let task = Task { await self.load(onError: onError) }
    loadTask = task
    await task.value
  }

  /// Stop the in-flight load. The detail view calls this on dismissal — see
  /// ``startLoad(onError:)`` for why the load outlives the task that started it.
  func cancelLoad() {
    loadTask?.cancel()
    loadTask = nil
  }

  /// Load everything a freshly-opened (or pulled-to-refresh) document needs from
  /// the server, best-effort.
  ///
  /// `loadDocument()` runs first and alone: it resolves the full-perms document
  /// (and so caches it, which the file-metadata version key depends on) before
  /// the PDF download validates the on-disk cache against the server's
  /// `modified`. The three enrichments — file-metadata, notes, edit suggestions —
  /// only need the document id, so they run concurrently afterwards.
  ///
  /// The PDF itself doesn't wait for that metadata round-trip, though: on a
  /// fresh open, a stored PDF for the already-known `document` is shown before
  /// any request, and `loadDocument` fires a provisional download off that
  /// (possibly stale) `document` in parallel with the metadata refresh to
  /// validate or replace it.
  ///
  /// Once metadata comes back — on *every* load, not just a fresh open — the
  /// resolved document's version/`modified` is compared against what was on
  /// screen, and a changed one triggers a re-download. That is what makes a
  /// pull-to-refresh pick up a version added server-side while the detail view
  /// was open.
  ///
  /// Each step always logs its failure. Whether it's *surfaced* is the caller's
  /// choice via `onError`: an on-appear load (`.task`) passes nothing and stays
  /// silent (the load isn't user-initiated, and the one critical failure — the
  /// PDF — already shows via `download == .error`); a pull-to-refresh passes a
  /// handler so failures toast. Offline-connectivity errors are dropped by
  /// `ErrorController.shouldSuppress`, so a parallel offline refresh won't spam.
  ///
  /// The four steps each hit the network independently, so a server-wide outage
  /// would otherwise fire `onError` once per step — three or four identical
  /// "could not connect" toasts for a single pull. To avoid that, failures are
  /// collected across the whole pass and each *distinct* error is surfaced once:
  /// a common outage collapses to one toast, while genuinely different failures
  /// (e.g. a permission error on a single endpoint) still each show.
  func load(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    let collector = onError == nil ? nil : LoadErrorCollector()
    let collect: (@MainActor @Sendable (any Error) -> Void)?
    if let collector {
      collect = { @MainActor @Sendable error in collector.add(error) }
    } else {
      collect = nil
    }

    await loadDocument(onError: collect)
    async let metadata: Void = loadMetadata(onError: collect)
    async let notes: Void = loadNotes(onError: collect)
    async let suggestions: Void = loadSuggestionsQuietly(onError: collect)
    _ = await (metadata, notes, suggestions)

    if let onError, let collector {
      for error in collector.distinct {
        onError(error)
      }
    }
  }

  func loadMetadata(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    do {
      metadata = try await store.repository.metadata(documentId: document.id)
    } catch let error where error.isCancellationError {
    } catch {
      Logger.shared.error("Error loading document metadata: \(error)")
      onError?(error)
    }
  }

  /// Warm the notes cache on open so they're available offline later. The notes
  /// view fetches its own (network-first) copy when presented; this just ensures
  /// a document opened online has its notes written through to the cache even if
  /// the user never taps the notes button. Routed through `store.notes(for:)` so
  /// the `.note` view-permission gate is respected.
  func loadNotes(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    do {
      _ = try await store.notes(for: document)
    } catch let error where error.isCancellationError {
    } catch {
      Logger.shared.error("Error loading document notes: \(error)")
      onError?(error)
    }
  }

  /// The quiet (open-path) form of `loadSuggestions()`: suggestions are an
  /// edit-sheet enrichment. `updateDocument()` calls the throwing
  /// `loadSuggestions()` directly, where the error propagates into the edit-save
  /// flow; here a failure is logged and only surfaced when `onError` is supplied.
  private func loadSuggestionsQuietly(onError: (@MainActor @Sendable (any Error) -> Void)?) async {
    do {
      try await loadSuggestions()
    } catch let error where error.isCancellationError {
    } catch {
      Logger.shared.error("Error loading document suggestions: \(error)")
      onError?(error)
    }
  }

  /// No PDF is on screen and none is in flight: either the document was just
  /// opened, or the last download failed and a refresh should retry it.
  private var hasNoPreview: Bool {
    switch download {
    case .initial, .error: true
    case .loading, .loaded: false
    }
  }

  /// Nothing on screen, or only an unconfirmed stored file.
  private var needsPreviewDownload: Bool {
    hasNoPreview || previewNeedsValidation
  }

  /// PDFKit's document when it can open the file at `url`, otherwise a named
  /// link for QuickLook; `nil` when neither works.
  private static func loadContent(
    url: URL, for document: Document, inMemory: Bool
  ) async -> DocumentContent? {
    let pdfDocument =
      inMemory
      ? await PDFDocument.loadBackgroundInMemory(url: url)
      : await PDFDocument.loadBackground(url: url)
    if let pdfDocument { return .pdf(pdfDocument) }
    Logger.shared.info("Document \(document.id) is not a PDF, previewing with QuickLook")
    // The link keeps the bytes it was made from if the store replaces the file.
    return NamedFileLink.stage(url, as: document.shareFilename(original: false)).map {
      .file($0)
    }
  }

  /// Show the stored PDF for `document`, if there is one, before any request
  /// is made. The server can take a long time to answer (e.g. disks spinning
  /// up), and the stored file is usually current.
  private func showStoredPreview(for document: Document) async {
    guard let url = await store.repository.storedDownload(document: document, original: false)
    else { return }
    let stamp = FileStamp(url: url)
    // Read into memory: the download that validates it may replace the file
    // at this same path while it is on screen.
    guard let content = await Self.loadContent(url: url, for: document, inMemory: true),
      case .initial = download
    else { return }
    download = .loaded(url: url, content: content)
    previewFileStamp = stamp
    previewNeedsValidation = true
  }

  func loadDocument(onError: (@MainActor @Sendable (any Error) -> Void)? = nil) async {
    let priorDocument = document

    if case .initial = download {
      await showStoredPreview(for: priorDocument)
    }

    // Fire the provisional PDF load off the already-known document right away
    // — its own cache check (ContentStore, keyed on `currentVersionID` +
    // `modified`) decides whether a stored preview is confirmed or replaced.
    // Runs on a refresh after a failed download too, so an unchanged document
    // is retried rather than left on the error placeholder.
    let provisionalDownload: Task<Void, Never>? =
      needsPreviewDownload ? Task { await runDownload(for: priorDocument) } : nil

    var accessRejected = false
    do {
      if let updated = try await store.document(id: document.id) {
        document = updated
        if let duplicates = updated.duplicates {
          self.duplicates = duplicates
        }
      }
    } catch let error where error.isCancellationError {
    } catch {
      accessRejected = Self.isAccessRejection(error)
      Logger.shared.error("Error updating document with full perms for editing: \(error)")
      onError?(error)
    }
    isDocumentLoaded = true

    // On a refresh with the PDF already on screen there is nothing to wait for
    // (`provisionalDownload` is nil).
    await provisionalDownload?.value

    // Applied after the provisional download, which may have just set
    // `.loaded` from the cache without asking the server.
    if accessRejected {
      clearPreview()
      return
    }

    // The original is otherwise only fetched after a preview download, which
    // an unchanged document with its preview on screen doesn't run.
    if case .error = originalDownload, case .loaded = download {
      Task { await downloadOriginal() }
    }

    // Nothing changed server-side — the PDF on screen (provisional or from a
    // previous load) already reflects current content, no need to re-fetch.
    //
    // The version check is what makes a server-side version bump visible: it
    // has to run on every load, not just a fresh open, or a document versioned
    // while the detail view is open keeps rendering the old file until the view
    // is closed and reopened. `runDownload` is safe to call here — its delayed
    // `.loading` flip only happens while no PDF is on screen, so the new PDF
    // swaps in without blanking the preview.
    guard
      document.currentVersionID != priorDocument.currentVersionID
        || document.modified != priorDocument.modified
    else { return }

    await runDownload(for: document)
  }

  private func runDownload(for document: Document) async {
    // A retry after a failed download shows loading like a fresh open does,
    // replacing the error placeholder. A PDF already on screen stays there.
    let setLoading =
      hasNoPreview
      ? Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        download = .loading
      } : nil
    // Cancel the delayed `.loading` flip on *every* exit path. Without this
    // the error path leaves `setLoading` pending, and 0.5s later it overwrites
    // the just-set `.error` back to `.loading` — pinning the preview's loading
    // overlay on screen even though the download already failed.
    defer { setLoading?.cancel() }
    // Delayed so a check that resolves straight from the cache doesn't flash.
    let showValidating =
      previewNeedsValidation
      ? Task {
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled else { return }
        isValidatingPreview = true
      } : nil
    defer {
      showValidating?.cancel()
      isValidatingPreview = false
    }
    do {
      let url = try await store.repository.download(
        document: document,
        original: false,
        progress: { @Sendable value in
          Task { @MainActor in
            self.downloadProgress = value
          }
        })

      let stamp = FileStamp(url: url)
      if case .loaded(let existingURL, _) = download, existingURL == url,
        stamp != nil, stamp == previewFileStamp
      {
        // The file on screen is the one the download resolved to.
        previewNeedsValidation = false
        Task { await downloadOriginal() }
        return
      }

      guard let content = await Self.loadContent(url: url, for: document, inMemory: false) else {
        if case .loaded = download {} else { download = .error }
        return
      }

      download = .loaded(url: url, content: content)
      previewFileStamp = stamp
      previewNeedsValidation = false

      // Start downloading the original in the background
      Task { await downloadOriginal() }
    } catch let error where error.isCancellationError {
    } catch {
      if case .loaded = download, !Self.isAccessRejection(error) {
        // The provisional PDF is already on screen; keep showing it rather
        // than clobbering it with an error from the post-metadata re-check.
        Logger.shared.error("Unable to refresh document preview after metadata update: \(error)")
      } else {
        clearPreview()
        Logger.shared.error("Unable to get document downloaded for preview rendering: \(error)")
      }
    }
  }

  /// The server answered 401 or 403: the user may no longer see this document,
  /// so a stored file must not stand in for it, however current it is.
  private static func isAccessRejection(_ error: any Error) -> Bool {
    switch error as? RequestError {
    case .forbidden, .unauthorized: true
    default: false
    }
  }

  private func clearPreview() {
    download = .error
    originalDownload = .initial
    previewFileStamp = nil
    previewNeedsValidation = false
  }

  /// Fetch the original file, unless it is already loaded or in flight. A
  /// previous failure is retried.
  func downloadOriginal() async {
    switch originalDownload {
    case .initial, .error: break
    case .loading, .loaded: return
    }
    originalDownload = .loading
    do {
      let url = try await store.repository.download(document: document, original: true)
      // The preview may have been cleared meanwhile; the original goes with it.
      guard case .loaded = download else {
        originalDownload = .initial
        return
      }
      originalDownload = .loaded(url: url)
    } catch {
      originalDownload = .error
      Logger.shared.error("Error downloading original document: \(error)")
    }
  }

  func loadSuggestions() async throws {
    suggestions = try await store.repository.suggestions(documentId: document.id)
  }

  func updateDocument() async throws {
    let updated = try await store.updateDocument(document)
    self.document = updated
    try await loadSuggestions()
  }

  var userCanChange: Bool {
    store.userCanChange(document: document)
  }

  var userCanView: Bool {
    store.userCanView(document: document)
  }

  var documentUrl: URL? {
    guard let connection else { return nil }
    return Endpoint.documentPage(documentId: document.id).url(url: connection.url)
  }

  // The server URL comes from the injected connection, not from downcasting
  // `store.repository`: the store holds a wrapper (`NeedsAuthRepository<ApiRepository>`),
  // so an `as? ApiRepository` cast silently fails and would drop the with-server link.
  var deepLinks: (withServer: Route?, withoutServer: Route?) {
    let withServer: Route? = connection.flatMap {
      guard let server = $0.url.stringDroppingScheme else { return nil }
      return Route(action: .document(id: document.id, edit: nil), server: server)
    }

    let withoutServer: Route? = Route(action: .document(id: document.id, edit: nil))
    return (withServer, withoutServer)

  }
}

/// Identity of a file on disk. A replacement arrives by rename, which gives the
/// path a different file number.
private struct FileStamp: Equatable {
  let fileNumber: Int
  let modified: Date?

  init?(url: URL) {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
      let fileNumber = attributes[.systemFileNumber] as? Int
    else { return nil }
    self.fileNumber = fileNumber
    modified = attributes[.modificationDate] as? Date
  }
}
