import Foundation
import Testing

@testable import Networking

@Suite struct MultiPartFormDataRequestTest {

  // Regression test for https://github.com/paulgessinger/swift-paperless/issues/624:
  // uploaded documents ended up 2 bytes larger than the original file because an
  // extra CRLF was written before the closing boundary.
  @Test func documentPartPreservesExactFileBytes() throws {
    // Binary-ish payload so this doesn't depend on the content being valid UTF-8.
    let fileData = Data([0x25, 0x50, 0x44, 0x46, 0x0D, 0x0A, 0x48, 0x45, 0x4C, 0x4C, 0x4F])
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("pdf")
    try fileData.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let mp = MultiPartFormDataRequest()
    mp.add(name: "title", string: "My Document")
    try mp.add(name: "document", url: tempURL, filename: "file.pdf")

    var request = URLRequest(url: URL(string: "https://example.com")!)
    mp.addTo(request: &request)

    let body = try #require(request.httpBody)
    let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
    let boundary = try #require(contentType.components(separatedBy: "boundary=").last)

    // Mirrors RFC 2046: a part's raw octets run from right after the blank
    // line ending its headers up to (but not including) the CRLF that starts
    // the next "--boundary" delimiter.
    let headerEnd = Data("\r\n\r\n".utf8)
    let delimiter = Data("\r\n--\(boundary)".utf8)

    let headerMarker = Data("name=\"document\"".utf8)
    let headerMarkerRange = try #require(body.range(of: headerMarker))
    let contentStart = try #require(
      body.range(of: headerEnd, in: headerMarkerRange.upperBound..<body.endIndex)
    ).upperBound
    let contentEnd = try #require(
      body.range(of: delimiter, in: contentStart..<body.endIndex)
    ).lowerBound

    let extracted = Data(body[contentStart..<contentEnd])
    #expect(extracted == fileData)
  }
}
