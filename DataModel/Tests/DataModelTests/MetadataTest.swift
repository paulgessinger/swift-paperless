//
//  MetadataTest.swift
//  DataModel
//
//  Created by Paul Gessinger on 03.01.25.
//

import Common
import Testing

@testable import DataModel

@Suite
struct MetadataTest {
  @Test func testDecoding() throws {
    let data = try #require(testData("Data/metadata.json"))

    let metadata = try makeDecoder(tz: .current).decode(Metadata.self, from: data)

    #expect(metadata.originalChecksum == "8e638f024cd9f14206dc63821f412844")
    #expect(metadata.originalSize == 49036)
    #expect(metadata.originalMimeType == "application/pdf")
    #expect(metadata.mediaFilename == "blurp/2024/12/2024-12-31--Bank somehing something.pdf")
    #expect(metadata.hasArchiveVersion == true)
    #expect(metadata.originalMetadata.count == 11)
    #expect(metadata.archiveChecksum == "04d626c75b075a2a88e896e46420044e")
    #expect(metadata.archiveMediaFilename == "blurp/2024/12/2024-12-31--Bank Statement.pdf")
    #expect(metadata.originalFilename == "E-Post_.pdf")
    #expect(metadata.archiveSize == 24376)
    #expect(metadata.archiveMetadata?.count == 10)
    #expect(metadata.lang == "en")
  }
}
