//
//  SearchablePDFPreview.swift
//  swift-paperless
//

import AppShared
import Common
import PDFKit
import SwiftUI

struct SearchablePDFPreview<TrailingContent: View>: View {
  private struct SearchablePDFView: UIViewRepresentable {
    let document: PDFDocument
    let bottomContentInset: CGFloat
    let initialPage: Int
    let extendsBehindTopBar: Bool
    @Binding var pdfView: PDFKit.PDFView?
    var onPageChange: (@MainActor @Sendable (Int) -> Void)?

    final class Coordinator: @unchecked Sendable {
      // Initial top-alignment should run once per loaded document.
      var didApplyInitialTopAlignment = false
      var didNavigateToInitialPage = false
      var scrollObservation: NSKeyValueObservation?
      var lastReportedPage: Int?
    }

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeUIView(context: Context) -> PDFKit.PDFView {
      let view = PDFKit.PDFView()
      // Keep PDFKit defaults close to the native viewer behavior.
      view.document = document
      view.displayMode = .singlePageContinuous
      view.pageShadowsEnabled = true
      view.autoScales = true
      view.displaysPageBreaks = true
      view.backgroundColor = .secondarySystemBackground
      view.isUserInteractionEnabled = true
      publishPDFView(view)

      // Seed the coordinator so the first observation that lands on the
      // initial page does not propagate as a "page changed" event.
      context.coordinator.lastReportedPage = initialPage

      if let scrollView = findScrollView(in: view) {
        let onPageChange = onPageChange
        let coordinator = context.coordinator
        coordinator.scrollObservation = scrollView.observe(
          \.contentOffset, options: [.new]
        ) { [weak view, weak scrollView] _, _ in
          MainActor.assumeIsolated {
            // Suppress any callbacks until the initial layout has been
            // applied — early KVO firings during initial sizing can otherwise
            // report a stale center page (e.g. before the offset is moved
            // below the navigation bar).
            guard coordinator.didApplyInitialTopAlignment else { return }
            guard let view, let document = view.document else { return }
            // Only react to user-initiated scrolling. Programmatic offset
            // changes (initial layout, sheet open/dismiss transitions, etc.)
            // shouldn't propagate back to the inline preview's page state.
            guard let scrollView,
              scrollView.isDragging || scrollView.isTracking
                || scrollView.isDecelerating
            else { return }

            let pageIndex: Int

            // If the user has scrolled to the bottom of the content, pin to
            // the last page — short pages can't scroll high enough for a
            // top-anchored probe to reach the last page otherwise.
            if Self.isScrolledToBottom(scrollView, threshold: 1) {
              pageIndex = max(0, document.pageCount - 1)
            } else {
              // Probe a point just below the top safe area / navigation bar
              // instead of the geometric centre. For short landscape pages
              // where multiple pages fit in the viewport, the centre lands
              // past page 0 and reports the wrong page on open.
              let topInset = view.safeAreaInsets.top
              let topProbe = CGPoint(
                x: view.bounds.midX,
                y: topInset + 40
              )

              if let page = view.page(for: topProbe, nearest: true) {
                pageIndex = document.index(for: page)
              } else if let current = view.currentPage {
                pageIndex = document.index(for: current)
              } else {
                return
              }
            }

            guard pageIndex != coordinator.lastReportedPage else { return }
            coordinator.lastReportedPage = pageIndex
            onPageChange?(pageIndex)
          }
        }
      }

      return view
    }

    func updateUIView(_ uiView: PDFKit.PDFView, context: Context) {
      publishPDFView(uiView)

      if uiView.document !== document {
        // Reset one-time layout fixes when the underlying document changes.
        uiView.document = document
        context.coordinator.didApplyInitialTopAlignment = false
      }
      applyInsetsAndInitialTopAlignmentIfNeeded(
        uiView,
        bottomInset: bottomContentInset,
        coordinator: context.coordinator
      )
    }

    private func applyInsetsAndInitialTopAlignmentIfNeeded(
      _ pdfView: PDFKit.PDFView,
      bottomInset: CGFloat,
      coordinator: Coordinator
    ) {
      guard let scrollView = findScrollView(in: pdfView) else {
        return
      }

      // Prevent UIKit from adding another automatic safe-area inset on top
      // of ours. This is set once — re-setting on every updateUIView causes
      // visible scroll jitter while the user is mid-fling.
      if scrollView.contentInsetAdjustmentBehavior != .never {
        scrollView.contentInsetAdjustmentBehavior = .never
      }

      let topInset = pdfView.safeAreaInsets.top
      // Guard the writes — `scrollView.contentInset = …` interrupts active
      // gestures and was the cause of the jittery kinetic scroll / "stuck
      // at the bottom" behaviour: SwiftUI re-runs updateUIView whenever any
      // observed state nearby changes, and each pass would clobber the
      // scroll's deceleration.
      if scrollView.contentInset.top != topInset
        || scrollView.contentInset.bottom != bottomInset
      {
        var contentInset = scrollView.contentInset
        contentInset.top = topInset
        contentInset.bottom = bottomInset
        scrollView.contentInset = contentInset

        var verticalIndicatorInset = scrollView.verticalScrollIndicatorInsets
        verticalIndicatorInset.top = topInset
        verticalIndicatorInset.bottom = bottomInset
        scrollView.verticalScrollIndicatorInsets = verticalIndicatorInset
      }

      guard !coordinator.didApplyInitialTopAlignment else {
        return
      }

      // When extending behind the top bar we expect topInset to be 0 (the
      // PDFView's safe area is excluded by `.ignoresSafeArea(edges: .top)`),
      // so skip the "wait for safe area" gate that would otherwise loop.
      if !extendsBehindTopBar, topInset == 0 {
        // Wait until layout/safe area is finalized before applying initial offset.
        DispatchQueue.main.async {
          applyInsetsAndInitialTopAlignmentIfNeeded(
            pdfView,
            bottomInset: bottomInset,
            coordinator: coordinator
          )
        }
        return
      }

      // Start aligned below the top bar, while still allowing later
      // scrolling under it. With `extendsBehindTopBar`, topInset is zero
      // and this is a no-op — the page starts at the top of the view,
      // visually behind the translucent toolbar.
      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: -topInset),
        animated: false
      )

      coordinator.didApplyInitialTopAlignment = true

      if !coordinator.didNavigateToInitialPage, initialPage > 0,
        let page = document.page(at: initialPage)
      {
        pdfView.go(to: page)
        // Adjust offset so the page starts below the top bar, not under it
        scrollView.contentOffset.y -= topInset
        coordinator.didNavigateToInitialPage = true
      }
    }

    private func publishPDFView(_ view: PDFKit.PDFView) {
      guard pdfView !== view else {
        return
      }

      DispatchQueue.main.async {
        guard pdfView !== view else {
          return
        }
        pdfView = view
      }
    }

    @MainActor
    private static func isScrolledToBottom(_ scrollView: UIScrollView, threshold: CGFloat) -> Bool {
      let maxOffsetY =
        scrollView.contentSize.height + scrollView.contentInset.bottom - scrollView.bounds.height
      return scrollView.contentOffset.y >= maxOffsetY - threshold
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
      if let scrollView = view as? UIScrollView {
        return scrollView
      }
      for subview in view.subviews {
        if let scrollView = findScrollView(in: subview) {
          return scrollView
        }
      }
      return nil
    }
  }

  let document: PDFDocument
  @Binding var currentPage: Int
  // When false, the leading X button is omitted — used on iPad where this
  // view is the primary content and there's no presentation to dismiss.
  var showsDismissButton: Bool = true
  // When true, the PDF view extends under the navigation bar so the page
  // scrolls behind a translucent toolbar. The page's first-paint position
  // and the indicator insets are kept where they are, just the frame
  // stretches up under the bar.
  var extendsBehindTopBar: Bool = false
  // Trailing content rendered to the right of the page indicator in the
  // bottom bar — used by iPad to merge document-level action buttons
  // (metadata/notes/delete) into the same row as search. iPhone leaves it
  // as `EmptyView` (via the convenience init below).
  let trailingContent: TrailingContent

  init(
    document: PDFDocument,
    currentPage: Binding<Int>,
    showsDismissButton: Bool = true,
    extendsBehindTopBar: Bool = false,
    @ViewBuilder trailingContent: () -> TrailingContent
  ) {
    self.document = document
    self._currentPage = currentPage
    self.showsDismissButton = showsDismissButton
    self.extendsBehindTopBar = extendsBehindTopBar
    self.trailingContent = trailingContent()
  }

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFieldFocused: Bool
  @State private var pdfView: PDFKit.PDFView?
  @State private var query = ""
  @State private var isSearchMode = false
  @State private var controller = PDFSearchController()
  @State private var bottomBarHeight: CGFloat = 0
  @State private var isSoftwareKeyboardVisible = false
  @State private var keyboardHeight: CGFloat = 0

  private var resultLabel: String? {
    if controller.matches.isEmpty {
      if query.isEmpty {
        return nil
      }
      // Distinguish "still scanning the document" from "no matches".
      return controller.isSearching ? "…" : "0"
    }

    return "\(controller.activeIndex + 1)/\(controller.matches.count)"
  }

  private var activeSearchBarVerticalPadding: CGFloat {
    let hasSoftwareKeyboard = isSoftwareKeyboardVisible || keyboardHeight > 100

    if isSearchFieldFocused && hasSoftwareKeyboard {
      return 12
    }

    return hasSoftwareKeyboard ? 24 : 34
  }

  @available(iOS 26.0, *)
  private var searchBar: some View {
    GlassEffectContainer {
      if isSearchMode {
        HStack(spacing: 8) {
          Button {
            setSearchMode(false)
            isSearchFieldFocused = false
          } label: {
            Label(localized: .app(.done), systemImage: "checkmark")
              .labelStyle(.iconOnly)
              .font(.title2)
              .bold()
              .padding(13)
              .foregroundStyle(.white)
          }
          .frame(maxHeight: .infinity)
          .glassEffect(.regular.tint(.accent).interactive(), in: Circle())

          TextField(.app(.search), text: $query)
            .focused($isSearchFieldFocused)
            .submitLabel(.search)

            .onChange(of: query) { _, _ in
              // Debounced, off-main search keeps the interaction fast.
              controller.setQuery(query)
            }
            .padding(.horizontal)
            .frame(maxHeight: .infinity)

            .overlay(alignment: .trailing) {
              HStack {
                if let resultLabel {
                  Text(resultLabel)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 42)
                }

                if !query.isEmpty {
                  Button {
                    query = ""
                  } label: {
                    Label(localized: .app(.clearText), systemImage: "xmark.circle.fill")
                      .labelStyle(.iconOnly)
                  }
                  .padding(.trailing)
                  .foregroundStyle(.secondary)
                }
              }
            }

            .glassEffect(.regular.interactive())

          HStack {
            Button {
              goToPrevious()
            } label: {
              Image(systemName: "chevron.up")
                .padding(.vertical)
                .padding(.leading)
            }
            .disabled(controller.matches.isEmpty)

            Button {
              goToNext()
            } label: {
              Image(systemName: "chevron.down")
                .padding(.vertical)
                .padding(.trailing)
            }
            .disabled(controller.matches.isEmpty)
          }
          .frame(maxHeight: .infinity)
          .glassEffect(.regular.interactive())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, activeSearchBarVerticalPadding)
        .fixedSize(horizontal: false, vertical: true)

      } else {
        // Page indicator goes in the geometric centre via ZStack; the
        // search button + optional trailing slot fill left/right and stay
        // vertically aligned with the centred indicator.
        ZStack {
          HStack {
            Button {
              setSearchMode(true)
              isSearchFieldFocused = true
            } label: {
              Label(localized: .app(.search), systemImage: "magnifyingglass")
                .labelStyle(.iconOnly)
                .font(.title2)
                .fontWeight(.semibold)
                .padding(13)
            }
            .glassEffect(.regular.interactive(), in: Circle())

            Spacer()

            trailingContent
          }

          if document.pageCount > 1 {
            Text(.app(.pageIndicator(currentPage + 1, document.pageCount)))
              .font(.footnote.monospacedDigit())
              .fontWeight(.semibold)
              .padding(.horizontal, 10)
              .padding(.vertical, 8)
              .glassEffect(.regular, in: Capsule())
              .contentTransition(.numericText())
              .animation(.default, value: currentPage)
          }
        }
        .padding(34)
      }
    }
    .animation(.spring(duration: 0.2), value: isSearchMode)
  }

  private var searchBarPreiOS26: some View {
    return VStack {
      if isSearchMode {
        // Solid bar: Done | recessed search field | prev/next arrows
        VStack(spacing: 0) {
          HStack(spacing: 12) {
            Button {
              setSearchMode(false)
              isSearchFieldFocused = false
            } label: {
              Text(.app(.done))
                .font(.body)
                .foregroundStyle(.primary)
            }

            TextField(.app(.search), text: $query)
              .focused($isSearchFieldFocused)
              .submitLabel(.search)
              .onChange(of: query) { _, _ in
                controller.setQuery(query)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                  .fill(Color(white: 0.9))
              )
              .overlay(alignment: .trailing) {
                HStack(spacing: 8) {
                  if let resultLabel {
                    Text(resultLabel)
                      .font(.footnote.monospacedDigit())
                      .foregroundStyle(.secondary)
                  }

                  if !query.isEmpty {
                    Button {
                      query = ""
                    } label: {
                      Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    }
                  }
                }
                .padding(.trailing, 8)
              }

            HStack(spacing: 4) {
              Button {
                goToPrevious()
              } label: {
                Image(systemName: "chevron.up")
                  .font(.body.weight(.medium))
              }
              .foregroundStyle(controller.matches.isEmpty ? .tertiary : .primary)
              .disabled(controller.matches.isEmpty)

              Button {
                goToNext()
              } label: {
                Image(systemName: "chevron.down")
                  .font(.body.weight(.medium))
              }
              .foregroundStyle(controller.matches.isEmpty ? .tertiary : .primary)
              .disabled(controller.matches.isEmpty)
            }
          }
          .padding(.horizontal, 20)
          .padding(.top)
          .padding(.bottom, 16)
          .frame(maxWidth: .infinity)

          // Grabber
          Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.bottom, 12)
        }
        .background(Rectangle().fill(Color(uiColor: .secondarySystemBackground)))
        .transition(.move(edge: .bottom))

      } else {
        // Compact bar with search icon only
        VStack(spacing: 0) {
          HStack {
            Button {
              setSearchMode(true)
              isSearchFieldFocused = true
            } label: {
              Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.accent)
            }

            Spacer()

            if document.pageCount > 1 {
              Text(.app(.pageIndicator(currentPage + 1, document.pageCount)))
                .font(.footnote.monospacedDigit())
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .contentTransition(.numericText())
                .animation(.default, value: currentPage)
            }
          }
          .padding(.horizontal, 24)
          .padding(.top, 24)
          .padding(.bottom, 16)

          // Grabber
          Capsule()
            .fill(.tertiary)
            .frame(width: 36, height: 5)
            .padding(.bottom, 12)
        }
        .background(
          Rectangle().fill(.thinMaterial)
            .stroke(Color(white: 0.8), lineWidth: 0.66)
        )
      }
    }
    .animation(.spring(duration: 0.2), value: isSearchMode)
  }

  @ViewBuilder
  private var bottomBar: some View {
    if #available(iOS 26.0, *) {
      searchBar
    } else {
      searchBarPreiOS26
    }
  }

  var body: some View {
    SearchablePDFView(
      document: document,
      bottomContentInset: max(bottomBarHeight, 44) + 0,
      initialPage: currentPage,
      extendsBehindTopBar: extendsBehindTopBar,
      pdfView: $pdfView,
      onPageChange: { @MainActor page in currentPage = page }
    )
    .ignoresSafeArea(
      .container,
      edges: extendsBehindTopBar ? [.top, .bottom] : .bottom
    )
    .safeAreaInset(edge: .bottom, spacing: 0) {
      bottomBar
        .readHeight { height in
          bottomBarHeight = height
        }
    }
    .trackKeyboardState(isVisible: $isSoftwareKeyboardVisible, height: $keyboardHeight)
    .onAppear {
      controller.configure(document: document)
    }
    .onChange(of: ObjectIdentifier(document)) { _, _ in
      controller.configure(document: document)
    }
    .onChange(of: controller.matches.count) { _, _ in
      // New matches streamed in — refresh the (capped) highlight overlay.
      updateHighlightedSelections()
    }
    .onChange(of: controller.focusToken) { _, _ in
      updateHighlightedSelections()
      focusCurrentMatch()
    }
    .toolbar {
      if showsDismissButton {
        ToolbarItem(placement: .topBarLeading) {
          CancelIconButton {
            dismiss()
          }
        }
      }
    }
    .onDisappear {
      // Avoid leaking search state when this sheet is dismissed and re-presented.
      setSearchMode(false)
    }

    .interactiveDismissDisabled(isSearchMode)
  }

  private func setSearchMode(_ enabled: Bool) {
    isSearchMode = enabled
    if !enabled {
      clearSearch()
    }
  }

  private func goToPrevious() {
    controller.previous()
  }

  private func goToNext() {
    controller.next()
  }

  private func clearSearch() {
    query = ""
    controller.clear()
    pdfView?.highlightedSelections = nil
    pdfView?.currentSelection = nil
  }

  private func focusCurrentMatch() {
    guard let pdfView else { return }
    let matches = controller.matches
    let index = controller.activeIndex
    guard matches.indices.contains(index) else { return }

    let match = matches[index]
    pdfView.currentSelection = match

    guard let page = match.pages.first else {
      pdfView.go(to: match)
      return
    }

    // The scroll observer ignores programmatic scrolling, so keep the page
    // indicator in sync ourselves when jumping to a match on another page.
    currentPage = document.index(for: page)

    // Rect-based navigation is far more reliable than `go(to: selection)` in
    // continuous layout. Grow the target upward so the hit lands a little
    // below the top edge rather than pinned under the toolbar.
    let target = match.bounds(for: page).insetBy(dx: 0, dy: -60)
    pdfView.go(to: target, on: page)
  }

  private func updateHighlightedSelections() {
    guard let pdfView else { return }

    let matches = controller.matches
    guard !matches.isEmpty else {
      pdfView.highlightedSelections = nil
      return
    }

    let activeIndex = controller.activeIndex
    let cap = PDFSearchHighlight.cap

    // Painting thousands of highlight rectangles on every page draw is what
    // makes huge result sets sluggish, so cap how many overlays PDFKit gets.
    // Within the cap we still split by line (cheap at <=500 selections) to
    // avoid oversized highlight rectangles on some PDFs.
    var highlighted: [PDFSelection] = []
    for index in 0..<min(matches.count, cap) {
      // Show all matches faintly, but make the active one visually stronger.
      let color =
        index == activeIndex
        ? PDFSearchHighlight.active
        : PDFSearchHighlight.inactive
      for line in matches[index].selectionsByLine() {
        line.color = color
        highlighted.append(line)
      }
    }

    // Always paint the active match strongly, even when it falls outside the
    // capped prefix on very large result sets.
    if activeIndex >= cap, matches.indices.contains(activeIndex) {
      for line in matches[activeIndex].selectionsByLine() {
        line.color = PDFSearchHighlight.active
        highlighted.append(line)
      }
    }

    // PDFView often needs a full reset to repaint highlight style changes.
    pdfView.highlightedSelections = nil
    pdfView.highlightedSelections = highlighted
  }

}

private enum PDFSearchHighlight {
  // Cap how many overlays PDFKit paints — drawing thousands of highlight
  // rectangles on every page draw is what makes huge result sets sluggish.
  static let cap = 500
  static let active = UIColor.systemYellow.withAlphaComponent(0.75)
  static let inactive = UIColor.systemYellow.withAlphaComponent(0.22)
}

// MARK: - Async PDF search

/// Wraps a batch of found selections so they can cross the background→main
/// boundary. `PDFSelection` isn't `Sendable`, but the hand-off is guarded by a
/// lock and the selections are only read on the main actor, so the unchecked
/// conformance is sound.
private struct PDFMatchBatch: @unchecked Sendable {
  let generation: Int
  let selections: [PDFSelection]
}

/// Runs PDF text search asynchronously, mirroring how the native viewer behaves.
///
/// `PDFDocument.findString(_:withOptions:)` is synchronous and walks the entire
/// document before returning, so running it on the main thread for a text-heavy
/// PDF blocks the UI long enough to trip the iOS watchdog (which surfaces as a
/// crash). Instead we drive `beginFindString`, which searches on a background
/// thread and streams matches through the delegate; results are coalesced and
/// published incrementally.
@MainActor
@Observable
final class PDFSearchController {
  private(set) var matches: [PDFSelection] = []
  private(set) var activeIndex = 0
  private(set) var isSearching = false
  /// Bumped whenever the active match should be scrolled into view.
  private(set) var focusToken = 0

  @ObservationIgnored private let finder = PDFFindDelegate()
  @ObservationIgnored private weak var document: PDFDocument?
  @ObservationIgnored private var debounceTask: Task<Void, Never>?
  /// Tags the search currently being displayed so stale streamed batches from
  /// a superseded query can be dropped.
  @ObservationIgnored private var liveGeneration = 0

  private static let debounce: Duration = .milliseconds(250)

  func configure(document: PDFDocument) {
    guard self.document !== document else { return }
    self.document = document

    finder.onBatch = { [weak self] batch in
      guard let self, batch.generation == self.liveGeneration else { return }
      let wasEmpty = self.matches.isEmpty
      self.matches.append(contentsOf: batch.selections)
      // Bring the first hit into view as soon as results start arriving.
      if wasEmpty {
        self.activeIndex = 0
        self.focusToken &+= 1
      }
    }
    finder.onEnd = { [weak self] generation in
      guard let self, generation == self.liveGeneration else { return }
      self.isSearching = false
    }

    document.delegate = finder
    resetState()
  }

  func setQuery(_ raw: String) {
    debounceTask?.cancel()
    let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      clear()
      return
    }
    let delay = Self.debounce
    debounceTask = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled else { return }
      self?.performSearch(term)
    }
  }

  func next() {
    guard !matches.isEmpty else { return }
    activeIndex = (activeIndex + 1) % matches.count
    focusToken &+= 1
  }

  func previous() {
    guard !matches.isEmpty else { return }
    activeIndex = (activeIndex - 1 + matches.count) % matches.count
    focusToken &+= 1
  }

  func clear() {
    debounceTask?.cancel()
    debounceTask = nil
    document?.cancelFindString()
    resetState()
  }

  private func performSearch(_ term: String) {
    guard let document else { return }
    document.cancelFindString()
    liveGeneration = finder.newSession()
    matches = []
    activeIndex = 0
    isSearching = true
    document.beginFindString(term, withOptions: [.caseInsensitive, .diacriticInsensitive])
  }

  private func resetState() {
    // Invalidate any in-flight batches and drop existing results.
    liveGeneration = finder.newSession()
    matches = []
    activeIndex = 0
    isSearching = false
  }
}

/// `PDFDocumentDelegate` that receives streamed matches on PDFKit's background
/// find thread, buffers them under a lock, and coalesces them into batched
/// main-thread updates.
private final class PDFFindDelegate: NSObject, PDFDocumentDelegate, @unchecked Sendable {
  private let lock = NSLock()
  private var buffer: [PDFSelection] = []
  private var generation = 0
  private var flushScheduled = false

  var onBatch: (@MainActor @Sendable (PDFMatchBatch) -> Void)?
  var onEnd: (@MainActor @Sendable (Int) -> Void)?

  /// Starts a fresh search session and returns its generation token so stale
  /// batches can be discarded.
  func newSession() -> Int {
    lock.lock()
    defer { lock.unlock() }
    generation += 1
    buffer.removeAll()
    flushScheduled = false
    return generation
  }

  // Called on PDFKit's background find thread. The instance is reused across
  // callbacks, so we must copy it to keep the match around.
  func didMatchString(_ instance: PDFSelection) {
    guard let copy = instance.copy() as? PDFSelection else { return }
    lock.lock()
    buffer.append(copy)
    let shouldSchedule = !flushScheduled
    flushScheduled = true
    lock.unlock()
    if shouldSchedule {
      Task { @MainActor [weak self] in self?.flush() }
    }
  }

  func documentDidEndDocumentFind(_ notification: Notification) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      self.flush()
      self.onEnd?(self.currentGeneration())
    }
  }

  private func currentGeneration() -> Int {
    lock.lock()
    defer { lock.unlock() }
    return generation
  }

  // Drains whatever has accumulated since the last flush so rapid matches
  // collapse into a single UI update. Match ordering doesn't matter: the buffer
  // is lock-protected and `documentDidEndDocumentFind` always flushes the tail.
  @MainActor
  private func flush() {
    lock.lock()
    flushScheduled = false
    let batch = PDFMatchBatch(generation: generation, selections: buffer)
    buffer.removeAll()
    lock.unlock()
    guard !batch.selections.isEmpty else { return }
    onBatch?(batch)
  }
}

extension SearchablePDFPreview where TrailingContent == EmptyView {
  init(
    document: PDFDocument,
    currentPage: Binding<Int>,
    showsDismissButton: Bool = true,
    extendsBehindTopBar: Bool = false
  ) {
    self.init(
      document: document,
      currentPage: currentPage,
      showsDismissButton: showsDismissButton,
      extendsBehindTopBar: extendsBehindTopBar,
      trailingContent: { EmptyView() }
    )
  }
}

extension View {
  fileprivate func readHeight(onChange: @escaping (CGFloat) -> Void) -> some View {
    overlay {
      GeometryReader { proxy in
        Color.clear
          .allowsHitTesting(false)
          .onAppear {
            onChange(proxy.size.height)
          }
          .onChange(of: proxy.size.height) { _, newValue in
            onChange(newValue)
          }
      }
    }
  }
}

#Preview {
  NavigationStack {
    SearchablePDFPreview(
      document: SearchablePDFPreviewPreviewData.document,
      currentPage: .constant(0)
    )
    .ignoresSafeArea()
  }
}

private enum SearchablePDFPreviewPreviewData {
  static var document: PDFDocument {
    let document = PDFDocument()
    let pages: [(title: String, body: String)] = [
      (
        "Sample PDF Preview - Page 1",
        "Use the Search button below to find matches across multiple pages."
      ),
      (
        "Sample PDF Preview - Page 2",
        "This page repeats the word preview several times. Preview text makes search testing easier."
      ),
      (
        "Sample PDF Preview - Page 3",
        "Final page with a different paragraph so scrolling and navigation can be validated."
      ),
    ]

    for (index, content) in pages.enumerated() {
      if let page = makePage(title: content.title, body: content.body) {
        document.insert(page, at: index)
      }
    }
    return document
  }

  private static func makePage(title: String, body: String) -> PDFPage? {
    let pageSize = CGSize(width: 612, height: 792)
    let renderer = UIGraphicsImageRenderer(size: pageSize)
    let image = renderer.image { context in
      UIColor.systemBackground.setFill()
      context.fill(CGRect(origin: .zero, size: pageSize))

      let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.preferredFont(forTextStyle: .title2),
        .foregroundColor: UIColor.label,
      ]
      let bodyAttributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.preferredFont(forTextStyle: .body),
        .foregroundColor: UIColor.secondaryLabel,
      ]

      title.draw(at: CGPoint(x: 40, y: 48), withAttributes: titleAttributes)
      body.draw(
        in: CGRect(x: 40, y: 96, width: pageSize.width - 80, height: 300),
        withAttributes: bodyAttributes
      )
    }
    return PDFPage(image: image)
  }
}
