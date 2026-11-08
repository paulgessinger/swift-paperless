//
//  ESCLMapping.swift
//  Scanning
//

import Foundation
import SwiftESCL
import UniformTypeIdentifiers

// Translation between SwiftESCL's vocabulary and ours. Everything here is
// synchronous and value-to-value, so it runs wherever its caller does and
// nothing non-`Sendable` outlives the call.

extension ScanSource {
  init?(_ source: InputSource) {
    switch source {
    case .platen: self = .flatbed
    case .adf: self = .feeder
    case .adfDuplex: self = .feederDuplex
    // eSCL's camera source is a live capture device, not a document scanner.
    case .camera: return nil
    }
  }

  var esclSource: InputSource {
    switch self {
    case .flatbed: .platen
    case .feeder: .adf
    case .feederDuplex: .adfDuplex
    }
  }
}

extension ScanColorMode {
  init?(_ mode: ColorMode) {
    switch mode {
    case .rgb24, .rgb48: self = .color
    case .grayscale8, .grayscale16: self = .grayscale
    case .blackAndWhite: self = .blackAndWhite
    }
  }

  /// The concrete eSCL mode to request, preferring the 8-bit variants the
  /// scanner actually offers. Falls back to the canonical one so a scanner with
  /// an unparseable capability document still gets a valid request.
  func esclMode(from supported: [ColorMode]) -> ColorMode {
    let candidates: [ColorMode] =
      switch self {
      case .color: [.rgb24, .rgb48]
      case .grayscale: [.grayscale8, .grayscale16]
      case .blackAndWhite: [.blackAndWhite]
      }

    return candidates.first(where: supported.contains) ?? candidates[0]
  }
}

extension ScanSourceCapabilities {
  init(_ caps: Capabilities) {
    // A scanner may list several eSCL modes that collapse onto one of ours.
    let modes = caps.colorModes.compactMap(ScanColorMode.init)
    let deduped = ScanColorMode.allCases.filter(modes.contains)

    self.init(
      colorModes: deduped.isEmpty ? ScanColorMode.allCases : deduped,
      resolutions: caps.supportedResolutions.sorted(),
      supportsPDF: caps.documentFormats.contains(.pdf)
    )
  }
}

extension ScannerCapabilities {
  init(_ raw: EsclScannerCapabilities, esclVersionFallback: String?) {
    var sources: [ScanSource: ScanSourceCapabilities] = [:]
    for (source, caps) in raw.sourceCapabilities {
      guard let source = ScanSource(source) else { continue }
      sources[source] = ScanSourceCapabilities(caps)
    }

    self.init(
      esclVersion: raw.version ?? esclVersionFallback,
      makeAndModel: raw.makeAndModel,
      sources: sources
    )
  }
}

extension ScanRequest {
  /// Builds the eSCL job description.
  ///
  /// - Parameter supportedModes: what the chosen source advertises, so the
  ///   colour mode lands on a value the scanner named itself. Empty is fine.
  func esclSettings(version: String, supportedModes: [ColorMode] = []) -> ScanSettings {
    ScanSettings(
      source: source.esclSource,
      version: version,
      mimeType: preferPDF ? .pdf : .jpeg,
      resolution: resolution,
      colorMode: colorMode.esclMode(from: supportedModes),
      // eSCL treats duplex as a flag on the feeder rather than a third source,
      // even though the capability document reports it as one.
      duplex: source == .feederDuplex ? true : nil
    )
  }
}

extension ScannerRef {
  /// Snapshots a discovered scanner.
  ///
  /// `usePlainText` comes from the browser rather than the scanner: SwiftESCL
  /// uses it to build the base URL and then forgets it, but we need it to
  /// rebuild an equivalent scanner later, and to tell the two transports apart
  /// when merging.
  init(_ scanner: EsclScanner, usePlainText: Bool) {
    self.init(
      id: scanner.id,
      hostname: scanner.hostname,
      port: scanner.port,
      root: scanner.root,
      usePlainText: usePlainText,
      model: scanner.model,
      location: scanner.location,
      esclVersion: scanner.esclVersion
    )
  }
}
