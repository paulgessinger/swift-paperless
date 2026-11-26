//
//  LibrarySizeEstimate.swift
//  DataModel
//

import Foundation

/// How much space a server's whole library would take on the device under
/// *Entire library*, estimated before any of it is downloaded.
///
/// The server has no figure for this, so it is extrapolated from the
/// documents whose file size is known: those whose file metadata is cached,
/// and those already downloaded. Pure arithmetic, kept here so it has a host
/// test; gathering the figures is `Persistence`'s job.
public struct LibrarySizeEstimate: Sendable, Equatable {
  /// What is known about one kind of file: how many documents' worth has a
  /// known size, and what those take together.
  public struct Known: Sendable, Equatable {
    public var documents: Int
    public var bytes: Int64

    public init(documents: Int = 0, bytes: Int64 = 0) {
      self.documents = documents
      self.bytes = bytes
    }

    fileprivate var average: Double? {
      documents > 0 ? Double(bytes) / Double(documents) : nil
    }
  }

  /// Per-document sizes assumed for a kind of file nothing is known about
  /// yet. Typical for scanned office documents; replaced by the real average
  /// as soon as one file of the kind is on the device.
  public enum Assumed {
    public static let thumbnailBytes: Double = 30_000
    /// A document's OCR text, compressed.
    public static let textBytes: Double = 2_500
    /// Its share of the full-text index.
    public static let searchIndexBytes: Double = 2_000
  }

  /// The library's documents, known to the device.
  public var documents: Int
  /// How many of them the document figure rests on. Equal to ``documents``
  /// when every file's size is known, and the figure is then exact.
  public var sampledDocuments: Int

  /// The document files (the archived PDFs).
  public var documentBytes: Int64
  public var thumbnailBytes: Int64
  /// The OCR texts and the full-text index over them.
  public var textBytes: Int64

  public var totalBytes: Int64 { documentBytes + thumbnailBytes + textBytes }

  /// Whether the document figure, which dominates the total, was measured
  /// rather than extrapolated.
  public var isExact: Bool { sampledDocuments >= documents }

  /// - Parameters:
  ///   - documents: The library's documents.
  ///   - files: The documents whose file size is known, and their sum.
  ///   - thumbnails: The thumbnails on the device.
  ///   - texts: The stored texts on the device.
  ///   - searchIndex: The documents in the full-text index and what it takes.
  /// - Returns: `nil` when there are documents but no file size is known:
  ///   there is nothing to extrapolate from.
  public static func estimate(
    documents: Int, files: Known, thumbnails: Known = Known(), texts: Known = Known(),
    searchIndex: Known = Known()
  ) -> LibrarySizeEstimate? {
    guard documents > 0 else {
      return LibrarySizeEstimate(
        documents: 0, sampledDocuments: 0, documentBytes: 0, thumbnailBytes: 0, textBytes: 0)
    }
    guard let fileAverage = files.average else { return nil }
    let count = Double(documents)
    // The known files as they are, the rest at their average.
    let sampled = min(files.documents, documents)
    let documentBytes = Double(files.bytes) + fileAverage * Double(documents - sampled)
    let perText =
      (texts.average ?? Assumed.textBytes) + (searchIndex.average ?? Assumed.searchIndexBytes)
    return LibrarySizeEstimate(
      documents: documents,
      sampledDocuments: sampled,
      documentBytes: Int64(documentBytes.rounded()),
      thumbnailBytes: Int64(((thumbnails.average ?? Assumed.thumbnailBytes) * count).rounded()),
      textBytes: Int64((perText * count).rounded()))
  }

  /// How many documents to know the size of before extrapolating: enough
  /// that one unusually large scan doesn't decide the figure.
  public static let targetSample = 40
}
