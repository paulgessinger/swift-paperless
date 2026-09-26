//
//  ScanOptionsTest.swift
//  Scanning
//

import Foundation
import SwiftESCL
import Testing
import UniformTypeIdentifiers

@testable import Scanning

@Suite
struct ScanOptionsTest {
  @Test func mapsEsclSourcesOntoTheOnesWeOffer() {
    #expect(ScanSource(.platen) == .flatbed)
    #expect(ScanSource(.adf) == .feeder)
    #expect(ScanSource(.adfDuplex) == .feederDuplex)
    // A live capture device is not a document scanner.
    #expect(ScanSource(.camera) == nil)
  }

  @Test func collapsesEsclColourModesOntoThree() {
    #expect(ScanColorMode(.rgb24) == .color)
    #expect(ScanColorMode(.rgb48) == .color)
    #expect(ScanColorMode(.grayscale8) == .grayscale)
    #expect(ScanColorMode(.grayscale16) == .grayscale)
    #expect(ScanColorMode(.blackAndWhite) == .blackAndWhite)
  }

  @Test func picksAnEsclModeTheScannerActuallyOffers() {
    #expect(ScanColorMode.color.esclMode(from: [.rgb48, .grayscale8]) == .rgb48)
    #expect(ScanColorMode.color.esclMode(from: [.rgb24, .rgb48]) == .rgb24)
    // Nothing advertised: fall back to the canonical mode rather than refusing.
    #expect(ScanColorMode.grayscale.esclMode(from: []) == .grayscale8)
  }

  @Test func dedupesColourModesThatCollapseOntoTheSameChoice() {
    let caps = ScanSourceCapabilities(
      Capabilities(
        colorModes: [.rgb48, .rgb24, .grayscale8],
        documentFormats: [.pdf],
        supportedResolutions: [300]
      ))

    #expect(caps.colorModes == [.color, .grayscale])
  }

  @Test func reportsPdfSupportFromTheAdvertisedFormats() {
    let withPDF = ScanSourceCapabilities(
      Capabilities(documentFormats: [.pdf, .jpeg], supportedResolutions: [300]))
    let withoutPDF = ScanSourceCapabilities(
      Capabilities(documentFormats: [.jpeg], supportedResolutions: [300]))

    #expect(withPDF.supportsPDF)
    #expect(!withoutPDF.supportsPDF)
  }

  @Test func offersEveryColourModeWhenTheScannerNamesNone() {
    let caps = ScanSourceCapabilities(Capabilities(supportedResolutions: [300]))
    #expect(caps.colorModes == ScanColorMode.allCases)
  }

  @Test func dropsSourcesWeDoNotOffer() {
    let raw = EsclScannerCapabilities(
      version: "2.6",
      makeAndModel: "Test Scanner",
      sourceCapabilities: [
        .platen: Capabilities(colorModes: [.rgb24], supportedResolutions: [300]),
        .camera: Capabilities(colorModes: [.rgb24], supportedResolutions: [300]),
      ]
    )

    let caps = ScannerCapabilities(raw, esclVersionFallback: nil)

    #expect(caps.availableSources == [.flatbed])
    #expect(caps.esclVersion == "2.6")
  }

  @Test func fallsBackToTheBonjourVersionWhenTheDocumentHasNone() {
    let caps = ScannerCapabilities(EsclScannerCapabilities(), esclVersionFallback: "2.0")
    #expect(caps.esclVersion == "2.0")
    #expect(caps.isEmpty)
  }

  @Test func ordersSourcesFlatbedFirstAndPrefersTheFeederByDefault() {
    let raw = EsclScannerCapabilities(sourceCapabilities: [
      .adfDuplex: Capabilities(supportedResolutions: [300]),
      .adf: Capabilities(supportedResolutions: [300]),
      .platen: Capabilities(supportedResolutions: [300]),
    ])

    let caps = ScannerCapabilities(raw, esclVersionFallback: nil)

    #expect(caps.availableSources == [.flatbed, .feeder, .feederDuplex])
    // A feeder is there to be used — but not duplex, which would interleave a
    // blank page into a stack of single-sided originals.
    #expect(caps.defaultSource == .feeder)
  }

  @Test func fallsBackToFlatbedWhenThereIsNoFeeder() {
    let raw = EsclScannerCapabilities(sourceCapabilities: [
      .platen: Capabilities(supportedResolutions: [300])
    ])
    #expect(ScannerCapabilities(raw, esclVersionFallback: nil).defaultSource == .flatbed)
  }

  @Test func fallbackCapabilitiesAreUsable() {
    let caps = ScannerCapabilities.fallback
    #expect(!caps.isEmpty)
    #expect(caps.availableSources == [.flatbed])
    #expect(caps.sources[.flatbed]?.resolutions.contains(300) == true)
  }

  @Test func defaultRequestAimsAtThreeHundredDpi() {
    let raw = EsclScannerCapabilities(sourceCapabilities: [
      .platen: Capabilities(
        colorModes: [.grayscale8, .rgb24],
        documentFormats: [.pdf],
        supportedResolutions: [75, 200, 600]
      )
    ])

    let request = ScanRequest(default: ScannerCapabilities(raw, esclVersionFallback: nil))

    #expect(request.source == .flatbed)
    #expect(request.colorMode == .color)
    #expect(request.resolution == 200)
    #expect(request.preferPDF)
  }

  @Test func defaultRequestSurvivesAnEmptyCapabilityDocument() {
    let request = ScanRequest(
      default: ScannerCapabilities(EsclScannerCapabilities(), esclVersionFallback: nil))

    #expect(request.source == .flatbed)
    #expect(request.colorMode == .color)
    #expect(request.resolution == 300)
    #expect(request.preferPDF)
  }

  @Test(arguments: [
    (target: 300, values: [150, 300, 600], expected: 300),
    (target: 300, values: [200, 400], expected: 200),
    (target: 300, values: [1200], expected: 1200),
  ])
  func picksTheClosestResolution(target: Int, values: [Int], expected: Int) {
    #expect(ScanRequest.closest(to: target, in: values) == expected)
  }

  @Test func duplexIsAFlagOnTheFeederNotAThirdSource() {
    let base = ScanRequest(source: .feeder, colorMode: .color, resolution: 300, preferPDF: true)
    var duplex = base
    duplex.source = .feederDuplex

    #expect(base.esclSettings(version: "2.0").duplex == nil)
    #expect(duplex.esclSettings(version: "2.0").duplex == true)
    #expect(duplex.esclSettings(version: "2.0").source == .adfDuplex)
  }

  @Test func requestsJpegWhenPdfIsNotAvailable() {
    let pdf = ScanRequest(source: .flatbed, colorMode: .color, resolution: 300, preferPDF: true)
    let jpeg = ScanRequest(source: .flatbed, colorMode: .color, resolution: 300, preferPDF: false)

    #expect(pdf.esclSettings(version: "2.0").mimeType == .pdf)
    #expect(jpeg.esclSettings(version: "2.0").mimeType == .jpeg)
  }
}
