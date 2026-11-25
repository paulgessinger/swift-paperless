import Testing

@testable import DataModel

@Suite("Library size estimate")
struct LibrarySizeEstimateTests {
  @Test("the known files count as they are and the rest at their average")
  func extrapolates() throws {
    let estimate = try #require(
      LibrarySizeEstimate.estimate(
        documents: 1000, files: .init(documents: 40, bytes: 4_000_000),
        thumbnails: .init(documents: 10, bytes: 200_000),
        texts: .init(documents: 5, bytes: 10_000),
        searchIndex: .init(documents: 5, bytes: 5_000)))
    // 4 MB known + 960 × 100 kB.
    #expect(estimate.documentBytes == 100_000_000)
    #expect(estimate.thumbnailBytes == 20_000_000)
    #expect(estimate.textBytes == 3_000_000)
    #expect(estimate.totalBytes == 123_000_000)
    #expect(estimate.sampledDocuments == 40)
    #expect(!estimate.isExact)
  }

  @Test("with every file known the document figure is exact")
  func exact() throws {
    let estimate = try #require(
      LibrarySizeEstimate.estimate(documents: 3, files: .init(documents: 3, bytes: 900)))
    #expect(estimate.documentBytes == 900)
    #expect(estimate.isExact)
  }

  @Test("kinds with nothing on the device yet use the assumed sizes")
  func assumedSizes() throws {
    let estimate = try #require(
      LibrarySizeEstimate.estimate(documents: 100, files: .init(documents: 1, bytes: 1000)))
    #expect(estimate.thumbnailBytes == 3_000_000)
    #expect(estimate.textBytes == 450_000)
  }

  @Test("no known file size means no estimate")
  func nothingKnown() {
    #expect(LibrarySizeEstimate.estimate(documents: 10, files: .init()) == nil)
  }

  @Test("an empty library takes nothing")
  func emptyLibrary() throws {
    let estimate = try #require(LibrarySizeEstimate.estimate(documents: 0, files: .init()))
    #expect(estimate.totalBytes == 0)
    #expect(estimate.isExact)
  }

  @Test("more known files than documents doesn't extrapolate backwards")
  func moreKnownThanDocuments() throws {
    // A document deleted since its size was read.
    let estimate = try #require(
      LibrarySizeEstimate.estimate(documents: 2, files: .init(documents: 3, bytes: 300)))
    #expect(estimate.documentBytes == 300)
    #expect(estimate.sampledDocuments == 2)
  }
}
