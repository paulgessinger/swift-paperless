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
    @Binding var pdfView: PDFKit.PDFView?

    func makeUIView(context _: Context) -> PDFKit.PDFView {
      let view = PDFKit.PDFView()
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

    func updateUIView(_ uiView: PDFKit.PDFView, context _: Context) {
      if uiView.document !== document {
        uiView.document = document
      }
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

  private var resultLabel: String {
    guard !matches.isEmpty else {
      return "0"
    }
    return "\(currentMatchIndex + 1)/\(matches.count)"
  }

  var body: some View {
    SearchablePDFView(document: document, pdfView: $pdfView)
      .background(Color(uiColor: .secondarySystemBackground))
      .safeAreaInset(edge: .bottom) {
        HStack(spacing: 8) {
          if isSearchMode {
            TextField("Search", text: $query)
              .textFieldStyle(.roundedBorder)
              .focused($isSearchFieldFocused)
              .submitLabel(.search)
              .onChange(of: query) { _, _ in
                runSearch()
              }

            Text(resultLabel)
              .font(.footnote.monospacedDigit())
              .foregroundStyle(.secondary)
              .frame(minWidth: 42)

            Button {
              goToPrevious()
            } label: {
              Image(systemName: "chevron.up")
            }
            .disabled(matches.isEmpty)

            Button {
              goToNext()
            } label: {
              Image(systemName: "chevron.down")
            }
            .disabled(matches.isEmpty)

            Button("Done") {
              setSearchMode(false)
              isSearchFieldFocused = false
            }
          } else {
            Spacer()
            Button {
              setSearchMode(true)
              isSearchFieldFocused = true
            } label: {
              Label("Search", systemImage: "magnifyingglass")
            }
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          CancelIconButton {
            onButtonDismiss()
            dismiss()
          }
        }
      }
      .onDisappear {
        setSearchMode(false)
      }
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
      copy.color =
        index == currentMatchIndex
        ? UIColor.systemYellow.withAlphaComponent(0.75)
        : UIColor.systemYellow.withAlphaComponent(0.22)
      return copy
    }

    pdfView.highlightedSelections = nil
    pdfView.highlightedSelections = highlightedSelections
  }
}
