//
//  NetworkScannerView.swift
//  swift-paperless
//

import AppShared
import PDFKit
import Scanning
import SwiftUI
import UIKit
import os

/// Finds an eSCL scanner on the local network, scans, and hands back a PDF.
///
/// The result joins the same path as the camera scanner and the file importer:
/// a local PDF URL for `DocumentImportModel`, which then opens
/// `CreateDocumentView`. Nothing about upload happens here.
///
/// This lives in the app target rather than `AppShared` on purpose — `AppShared`
/// is a dependency of the ShareExtension, and the extension has no use for
/// scanner discovery.
struct NetworkScannerView: View {
  let onCompletion: (URL) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var discovery = ScannerDiscovery()
  @State private var stage: Stage = .discovery
  @State private var scanTask: Task<Void, Never>?
  @State private var errorMessage: String?

  private enum Stage {
    case discovery
    case settings(ScannerRef)
    case scanning(ScannerRef)
  }

  var body: some View {
    NavigationStack {
      Group {
        switch stage {
        case .discovery:
          DiscoveryList(scanners: discovery.scanners) { stage = .settings($0) }
        case .settings(let ref):
          ScanSettingsList(scanner: ref) { request in
            start(scanning: ref, with: request)
          }
        case .scanning(let ref):
          ScanProgressView(scanner: ref, progress: progress) { cancel() }
        }
      }
      .navigationTitle(String(localized: .app(.networkScannerTitle)))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: .app(.cancel))) { cancel() }
        }
      }
      .alert(
        String(localized: .app(.errorDefaultMessage)),
        isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
      ) {
        Button(String(localized: .app(.ok))) { errorMessage = nil }
      } message: {
        if let errorMessage { Text(errorMessage) }
      }
    }
    .task {
      // Starting here rather than at init is what keeps the Local Network
      // permission prompt tied to the user asking for a scanner.
      discovery.start()
    }
    .onDisappear {
      discovery.stop()
      scanTask?.cancel()
    }
  }

  @State private var progress: Double = 0

  private func start(scanning ref: ScannerRef, with request: ScanRequest) {
    // Discovery competes with the scan for the same device, and the chosen
    // `ScannerRef` is already frozen — nothing left to find.
    discovery.stop()
    progress = 0
    stage = .scanning(ref)

    scanTask = Task {
      let (stream, continuation) = AsyncStream<Double>.makeStream()
      // One consumer on the main actor keeps the updates in order; a hop per
      // callback would let the bar run backwards.
      let consumer = Task { @MainActor in
        for await fraction in stream { progress = fraction }
      }
      defer { consumer.cancel() }

      do {
        let pages = try await ScannerClient.scan(ref, request, progress: continuation)
        let url = try assemblePDF(from: pages)
        onCompletion(url)
        dismiss()
      } catch is CancellationError {
        Logger.scanning.info("Network scan cancelled")
        stage = .settings(ref)
      } catch {
        Logger.scanning.error("Network scan failed: \(String(describing: error))")
        errorMessage = message(for: error)
        stage = .settings(ref)
      }
    }
  }

  private func cancel() {
    scanTask?.cancel()
    scanTask = nil
    discovery.stop()
    dismiss()
  }
}

// MARK: - Stages

private struct DiscoveryList: View {
  let scanners: [ScannerRef]
  let onSelect: (ScannerRef) -> Void

  /// How long to look like we are still searching before admitting there is
  /// nothing there. Bonjour has no "done" — scanners simply stop arriving.
  private static let patience: Duration = .seconds(6)

  @State private var gaveUp = false

  var body: some View {
    List {
      ForEach(scanners) { scanner in
        Button {
          onSelect(scanner)
        } label: {
          row(for: scanner)
        }
        .buttonStyle(.plain)
      }
    }
    .overlay {
      placeholder
    }
    .task {
      gaveUp = false
      try? await Task.sleep(for: Self.patience)
      gaveUp = true
    }
  }

  @ViewBuilder
  private var placeholder: some View {
    if scanners.isEmpty {
      if gaveUp {
        ContentUnavailableView {
          Label(localized: .app(.networkScannerNoneFound), systemImage: "scanner")
        } description: {
          Text(.app(.networkScannerNoneFoundHint))
        }
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text(.app(.networkScannerSearching))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private func row(for scanner: ScannerRef) -> some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(scanner.displayName)
        if let location = scanner.location, !location.isEmpty {
          Text(location)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      Spacer()
      if !scanner.usePlainText {
        Image(systemName: "lock")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
      Image(systemName: "chevron.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.tertiary)
    }
    .contentShape(.rect)
  }
}

private struct ScanSettingsList: View {
  let scanner: ScannerRef
  let onScan: (ScanRequest) -> Void

  @State private var loaded: (capabilities: ScannerCapabilities, request: ScanRequest)?

  var body: some View {
    Group {
      if let loaded {
        ScanSettingsForm(
          scanner: scanner,
          capabilities: loaded.capabilities,
          request: loaded.request,
          onScan: onScan
        )
      } else {
        VStack(spacing: 12) {
          ProgressView()
          Text(.app(.networkScannerLoadingCapabilities))
            .foregroundStyle(.secondary)
        }
      }
    }
    .task(id: scanner.id) {
      let resolved: ScannerCapabilities
      do {
        let reported = try await ScannerClient.capabilities(of: scanner)
        // A capability document we could not parse is not a reason to refuse
        // to scan — offer the combination every eSCL device supports.
        resolved = reported.isEmpty ? .fallback : reported
      } catch {
        Logger.scanning.warning(
          "Could not read scanner capabilities: \(String(describing: error))")
        resolved = .fallback
      }

      loaded = (resolved, ScanRequest(default: resolved))
    }
  }
}

private struct ScanSettingsForm: View {
  let scanner: ScannerRef
  let capabilities: ScannerCapabilities
  let onScan: (ScanRequest) -> Void

  @State private var request: ScanRequest

  init(
    scanner: ScannerRef,
    capabilities: ScannerCapabilities,
    request: ScanRequest,
    onScan: @escaping (ScanRequest) -> Void
  ) {
    self.scanner = scanner
    self.capabilities = capabilities
    self.onScan = onScan
    _request = State(initialValue: request)
  }

  var body: some View {
    Form {
      Section {
        Picker(String(localized: .app(.networkScannerSource)), selection: $request.source) {
          ForEach(capabilities.availableSources, id: \.self) { source in
            Text(source.label).tag(source)
          }
        }

        Picker(String(localized: .app(.networkScannerColorMode)), selection: $request.colorMode) {
          ForEach(colorModes, id: \.self) { mode in
            Text(mode.label).tag(mode)
          }
        }

        Picker(String(localized: .app(.networkScannerResolution)), selection: $request.resolution) {
          ForEach(resolutions, id: \.self) { dpi in
            Text(.app(.networkScannerResolutionValue(dpi))).tag(dpi)
          }
        }
      } header: {
        Text(scanner.displayName)
      }

      Section {
        Button {
          onScan(request)
        } label: {
          Label(localized: .app(.networkScannerScanButton), systemImage: "scanner")
            .frame(maxWidth: .infinity)
        }
      }
    }
    // Switching source changes which modes and resolutions exist, so re-derive
    // rather than leaving a selection the new source cannot honour.
    .onChange(of: request.source) { _, source in
      guard let caps = capabilities.sources[source] else { return }
      if !caps.colorModes.contains(request.colorMode) {
        request.colorMode = caps.colorModes.first ?? .color
      }
      if !caps.resolutions.isEmpty, !caps.resolutions.contains(request.resolution) {
        request.resolution =
          ScanRequest.closest(to: 300, in: caps.resolutions) ?? request.resolution
      }
      request.preferPDF = caps.supportsPDF
    }
  }

  private var colorModes: [ScanColorMode] {
    let reported = capabilities.sources[request.source]?.colorModes ?? []
    return reported.isEmpty ? ScanColorMode.allCases : reported
  }

  private var resolutions: [Int] {
    let reported = capabilities.sources[request.source]?.resolutions ?? []
    // Always include what is selected, so the picker cannot end up with a
    // selection none of its rows carry.
    return reported.contains(request.resolution)
      ? reported : (reported + [request.resolution]).sorted()
  }
}

private struct ScanProgressView: View {
  let scanner: ScannerRef
  let progress: Double
  let onCancel: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text(.app(.networkScannerScanning))
        .font(.headline)
      Text(scanner.displayName)
        .foregroundStyle(.secondary)
      ProgressView(value: progress)
        .frame(maxWidth: 260)
      Button(String(localized: .app(.cancel)), role: .cancel, action: onCancel)
        .padding(.top, 8)
    }
    .padding()
  }
}

// MARK: - Presentation

extension ScanSource {
  fileprivate var label: String {
    switch self {
    case .flatbed: String(localized: .app(.networkScannerSourceFlatbed))
    case .feeder: String(localized: .app(.networkScannerSourceFeeder))
    case .feederDuplex: String(localized: .app(.networkScannerSourceFeederDuplex))
    }
  }
}

extension ScanColorMode {
  fileprivate var label: String {
    switch self {
    case .color: String(localized: .app(.networkScannerColorModeColor))
    case .grayscale: String(localized: .app(.networkScannerColorModeGray))
    case .blackAndWhite: String(localized: .app(.networkScannerColorModeBlackWhite))
    }
  }
}

private func message(for error: any Error) -> String {
  switch error {
  case ScanError.unreachable: String(localized: .app(.networkScannerErrorUnreachable))
  case ScanError.busy: String(localized: .app(.networkScannerErrorBusy))
  case ScanError.noPages: String(localized: .app(.networkScannerErrorNoPages))
  case ScanError.malformedDocument: String(localized: .app(.networkScannerErrorMalformed))
  case ScanError.timedOut: String(localized: .app(.networkScannerErrorTimedOut))
  case ScanError.scannerReported(let detail):
    String(localized: .app(.networkScannerErrorReported(detail)))
  default: error.localizedDescription
  }
}

/// Folds the scanner's payloads into one PDF.
///
/// eSCL hands back one document per scanned sheet, so even a PDF request comes
/// back as several single-page PDFs. One loop covers both that and the JPEG
/// case — `createPDFFrom(images:)` only handles the latter, and would leave the
/// PDF branch duplicated here anyway.
private func assemblePDF(from pages: [Data]) throws -> URL {
  let document = PDFDocument()

  for data in pages {
    if let scanned = PDFDocument(data: data) {
      for index in 0..<scanned.pageCount {
        guard let page = scanned.page(at: index) else { continue }
        document.insert(page, at: document.pageCount)
      }
    } else if let image = UIImage(data: data) {
      guard let page = PDFPage(image: image) else {
        throw DocumentImportError.pdfCreatePageFailed
      }
      document.insert(page, at: document.pageCount)
    } else {
      throw ScanError.malformedDocument
    }
  }

  guard document.pageCount > 0 else { throw ScanError.noPages }

  let url = FileManager.default.temporaryDirectory
    .appending(component: formattedImportFilename())
    .appendingPathExtension("pdf")

  guard document.write(to: url) else { throw DocumentImportError.pdfWriteFailed }
  return url
}
