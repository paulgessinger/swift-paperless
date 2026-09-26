//
//  ScanOptions.swift
//  Scanning
//

import Foundation

/// Where the paper comes from.
public enum ScanSource: String, Sendable, CaseIterable, Hashable {
  case flatbed
  case feeder
  case feederDuplex
}

/// The colour modes we expose. eSCL has more (16-bit variants, colour spaces,
/// CCD channel selection); these are the three a user picking "scan this
/// receipt" actually wants.
public enum ScanColorMode: String, Sendable, CaseIterable, Hashable {
  case color
  case grayscale
  case blackAndWhite
}

/// What one source of a scanner can do, reduced to the choices the UI offers.
public struct ScanSourceCapabilities: Sendable, Hashable {
  public let colorModes: [ScanColorMode]
  public let resolutions: [Int]
  /// `true` when the scanner advertises PDF output for this source. When it
  /// does not we request JPEG and assemble the PDF ourselves.
  public let supportsPDF: Bool

  public init(colorModes: [ScanColorMode], resolutions: [Int], supportsPDF: Bool) {
    self.colorModes = colorModes
    self.resolutions = resolutions
    self.supportsPDF = supportsPDF
  }
}

/// A scanner's capabilities, as values.
public struct ScannerCapabilities: Sendable, Hashable {
  public let esclVersion: String?
  public let makeAndModel: String?
  public let sources: [ScanSource: ScanSourceCapabilities]

  public init(
    esclVersion: String?, makeAndModel: String?, sources: [ScanSource: ScanSourceCapabilities]
  ) {
    self.esclVersion = esclVersion
    self.makeAndModel = makeAndModel
    self.sources = sources
  }

  /// The sources to offer, in the order they should appear.
  public var availableSources: [ScanSource] {
    ScanSource.allCases.filter { sources[$0] != nil }
  }

  /// What to preselect. A feeder is there to be used, so prefer it; duplex is
  /// not the default because a stack of single-sided pages would come back with
  /// a blank between every page.
  public var defaultSource: ScanSource? {
    availableSources.first { $0 == .feeder } ?? availableSources.first
  }

  /// A scanner whose capability document we could not parse reports nothing.
  ///
  /// SwiftESCL's capability parser matches literal namespace prefixes
  /// (`scan:platen`) without enabling namespace processing, so a scanner that
  /// declares eSCL under a different prefix yields an empty document rather
  /// than an error. Callers substitute ``ScannerCapabilities/fallback`` so the
  /// user gets working pickers instead of empty ones.
  public var isEmpty: Bool { sources.isEmpty }

  /// What to offer when the scanner told us nothing usable. Flatbed colour at
  /// 300 dpi is the one combination essentially every eSCL device supports.
  public static let fallback = ScannerCapabilities(
    esclVersion: nil,
    makeAndModel: nil,
    sources: [
      .flatbed: ScanSourceCapabilities(
        colorModes: ScanColorMode.allCases,
        resolutions: [150, 200, 300, 600],
        supportsPDF: true
      )
    ]
  )
}

/// One scan, as the user configured it.
public struct ScanRequest: Sendable, Hashable {
  public var source: ScanSource
  public var colorMode: ScanColorMode
  public var resolution: Int
  /// Ask the scanner for PDF rather than JPEG. Either way the caller ends up
  /// assembling one PDF, because eSCL hands back one payload per document and a
  /// flatbed scan of several pages is several payloads.
  public var preferPDF: Bool

  public init(source: ScanSource, colorMode: ScanColorMode, resolution: Int, preferPDF: Bool) {
    self.source = source
    self.colorMode = colorMode
    self.resolution = resolution
    self.preferPDF = preferPDF
  }

  /// The request to preselect for `capabilities`, honouring what the scanner
  /// says it can do and aiming at 300 dpi — enough for OCR without producing
  /// files Paperless has to chew through.
  public init(default capabilities: ScannerCapabilities) {
    let source = capabilities.defaultSource ?? .flatbed
    let caps = capabilities.sources[source]

    self.source = source
    colorMode =
      caps?.colorModes.contains(.color) == true ? .color : (caps?.colorModes.first ?? .color)
    resolution = Self.closest(to: 300, in: caps?.resolutions ?? []) ?? 300
    preferPDF = caps?.supportsPDF ?? true
  }

  /// The value nearest `target`, or `nil` when there are none to choose from.
  public static func closest(to target: Int, in values: [Int]) -> Int? {
    values.min { abs($0 - target) < abs($1 - target) }
  }
}
