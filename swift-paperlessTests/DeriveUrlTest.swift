import XCTest

final class DeriveUrlTest: XCTestCase {
    func testBasicFunctionality() throws {
        let res = deriveUrl(string: "paperless.example.com")
        XCTAssertNotNil(res)
        let (base, url) = res!

        XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
        XCTAssertEqual(url, URL(string: "https://paperless.example.com/api"))
    }
}
