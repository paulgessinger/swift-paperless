import XCTest

final class DeriveUrlTest: XCTestCase {
    func testBasicFunctionality() throws {
        do {
            _ = try deriveUrl(string: "file://paperless.example.com")
        }

        do {
            // implicit https scheme
            let (base, url) = try deriveUrl(string: "paperless.example.com")

            XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/"))
        }
    }

    func testMissingHostname() throws {
        let res = try deriveUrl(string: "http://")
        XCTAssertNil(res)
    }

    func testExplicitScheme() throws {
        do {
            let (base, url) = try deriveUrl(string: "http://paperless.example.com")
            XCTAssertEqual(base, URL(string: "http://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "http://paperless.example.com/api/"))
        }

        do {
            let (base, url) = try deriveUrl(string: "https://paperless.example.com")
            XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/"))
        }
    }

    func testSuffix() throws {
        let (base, url) = try deriveUrl(string: "https://paperless.example.com", suffix: "token")
        XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
        XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/token/"))
    }
}
