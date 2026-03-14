//
//  SearchablePDFPreview.swift
//  swift-paperless
//

import Common
import PDFKit
import SwiftUI

struct SearchablePDFPreview: View {
  private struct SearchablePDFView: UIViewRepresentable {
    let document: PDFDocument
    let bottomContentInset: CGFloat
    @Binding var pdfView: PDFKit.PDFView?

    final class Coordinator {
      // Initial top-alignment should run once per loaded document.
      var didApplyInitialTopAlignment = false
    }

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }

    func makeUIView(context _: Context) -> PDFKit.PDFView {
      let view = PDFKit.PDFView()
      // Keep PDFKit defaults close to the native viewer behavior.
      view.document = document
      view.displayMode = .singlePageContinuous
      view.pageShadowsEnabled = true
      view.autoScales = true
      view.displaysPageBreaks = true
      view.backgroundColor = .secondarySystemBackground
      view.isUserInteractionEnabled = true
      pdfView = view
      return view
    }

    func updateUIView(_ uiView: PDFKit.PDFView, context: Context) {
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

      // Prevent UIKit from adding another automatic safe-area inset on top of ours.
      scrollView.contentInsetAdjustmentBehavior = .never

      let topInset = pdfView.safeAreaInsets.top
      var contentInset = scrollView.contentInset
      contentInset.top = topInset
      contentInset.bottom = bottomInset
      scrollView.contentInset = contentInset

      // Keep the scroll indicator aligned with the visible content start.
      var verticalIndicatorInset = scrollView.verticalScrollIndicatorInsets
      verticalIndicatorInset.top = topInset
      verticalIndicatorInset.bottom = bottomInset
      scrollView.verticalScrollIndicatorInsets = verticalIndicatorInset

      guard !coordinator.didApplyInitialTopAlignment else {
        return
      }
      guard topInset > 0 else {
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

      // Start aligned below the top bar, while still allowing later scrolling under it.
      scrollView.setContentOffset(
        CGPoint(x: scrollView.contentOffset.x, y: -topInset),
        animated: false
      )

      coordinator.didApplyInitialTopAlignment = true
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
  let onButtonDismiss: () -> Void

  @Environment(\.dismiss) private var dismiss
  @FocusState private var isSearchFieldFocused: Bool
  @State private var pdfView: PDFKit.PDFView?
  @State private var query = ""
  @State private var isSearchMode = false
  @State private var matches = [PDFSelection]()
  @State private var currentMatchIndex = 0
  @State private var bottomBarHeight: CGFloat = 0
  @State private var isSoftwareKeyboardVisible = false
  @State private var keyboardHeight: CGFloat = 0

  private var resultLabel: String? {
    if matches.isEmpty {
      if query.isEmpty {
        return nil
      } else {
        return "0"
      }
    }

    return "\(currentMatchIndex + 1)/\(matches.count)"
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
            Label(localized: .localizable(.done), systemImage: "checkmark")
              .labelStyle(.iconOnly)
              .font(.title2)
              .bold()
              .padding(13)
              .foregroundStyle(.white)
          }
          .frame(maxHeight: .infinity)
          .glassEffect(.regular.tint(.accent).interactive(), in: Circle())

          TextField(.localizable(.search), text: $query)
            .focused($isSearchFieldFocused)
            .submitLabel(.search)

            .onChange(of: query) { _, _ in
              // Live-search keeps the interaction fast and predictable.
              runSearch()
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
                    Label(localized: .localizable(.clearText), systemImage: "xmark.circle.fill")
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
            .disabled(matches.isEmpty)

            Button {
              goToNext()
            } label: {
              Image(systemName: "chevron.down")
                .padding(.vertical)
                .padding(.trailing)
            }
            .disabled(matches.isEmpty)
          }
          .frame(maxHeight: .infinity)
          .glassEffect(.regular.interactive())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, activeSearchBarVerticalPadding)
        .fixedSize(horizontal: false, vertical: true)

      } else {
        Button {
          setSearchMode(true)
          isSearchFieldFocused = true
        } label: {
          Label(localized: .localizable(.search), systemImage: "magnifyingglass")
            .labelStyle(.iconOnly)
            .font(.title2)
            .bold()
            .padding(13)
        }
        .glassEffect(.regular.interactive(), in: Circle())
        .frame(maxWidth: .infinity, alignment: .leading)
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
              Text(.localizable(.done))
                .font(.body)
                .foregroundStyle(.primary)
            }

            TextField(.localizable(.search), text: $query)
              .focused($isSearchFieldFocused)
              .submitLabel(.search)
              .onChange(of: query) { _, _ in
                runSearch()
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
              .foregroundStyle(matches.isEmpty ? .tertiary : .primary)
              .disabled(matches.isEmpty)

              Button {
                goToNext()
              } label: {
                Image(systemName: "chevron.down")
                  .font(.body.weight(.medium))
              }
              .foregroundStyle(matches.isEmpty ? .tertiary : .primary)
              .disabled(matches.isEmpty)
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
          Button {
            setSearchMode(true)
            isSearchFieldFocused = true
          } label: {
            Image(systemName: "magnifyingglass")
              .font(.title2)
              .foregroundStyle(.accent)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
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
      pdfView: $pdfView
    )
    .ignoresSafeArea(.container, edges: .bottom)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      bottomBar
        .readHeight { height in
          bottomBarHeight = height
        }
    }
    .trackKeyboardState(isVisible: $isSoftwareKeyboardVisible, height: $keyboardHeight)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        CancelIconButton {
          onButtonDismiss()
          dismiss()
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
    guard !matches.isEmpty else {
      return
    }
    currentMatchIndex = (currentMatchIndex - 1 + matches.count) % matches.count
    focusCurrentMatch()
  }

  private func goToNext() {
    guard !matches.isEmpty else {
      return
    }
    currentMatchIndex = (currentMatchIndex + 1) % matches.count
    focusCurrentMatch()
  }

  private func runSearch() {
    guard
      let pdfView,
      let document = pdfView.document
    else {
      return
    }

    let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !term.isEmpty else {
      clearSearch()
      return
    }

    let rawSelections = document.findString(
      term,
      withOptions: [.caseInsensitive, .diacriticInsensitive]
    )
    // Line-level selections avoid oversized highlight rectangles on some PDFs.
    let foundSelections = rawSelections.flatMap { $0.selectionsByLine() }

    matches = foundSelections
    currentMatchIndex = 0
    updateHighlightedSelections(pdfView: pdfView)
    focusCurrentMatch()
  }

  private func focusCurrentMatch() {
    guard
      let pdfView,
      !matches.isEmpty,
      matches.indices.contains(currentMatchIndex)
    else {
      if let pdfView {
        updateHighlightedSelections(pdfView: pdfView)
      } else {
        pdfView?.highlightedSelections = matches.isEmpty ? nil : matches
      }
      return
    }

    let match = matches[currentMatchIndex]
    updateHighlightedSelections(pdfView: pdfView)
    // Keep the active match visually selected and in view.
    pdfView.currentSelection = match
    pdfView.go(to: match)
  }

  private func clearSearch() {
    query = ""
    matches = []
    currentMatchIndex = 0
    pdfView?.highlightedSelections = nil
    pdfView?.currentSelection = nil
  }

  private func updateHighlightedSelections(pdfView: PDFKit.PDFView) {
    guard !matches.isEmpty else {
      pdfView.highlightedSelections = nil
      return
    }

    let highlightedSelections = matches.enumerated().compactMap {
      index, selection -> PDFSelection? in
      guard let copy = selection.copy() as? PDFSelection else {
        return nil
      }
      // Show all matches, but make the active one visually stronger.
      copy.color =
        index == currentMatchIndex
        ? UIColor.systemYellow.withAlphaComponent(0.75)
        : UIColor.systemYellow.withAlphaComponent(0.22)
      return copy
    }

    // PDFView often needs a full reset to repaint highlight style changes.
    pdfView.highlightedSelections = nil
    pdfView.highlightedSelections = highlightedSelections
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
      onButtonDismiss: {}
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
