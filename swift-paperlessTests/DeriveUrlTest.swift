import XCTest

final class DeriveUrlTest: XCTestCase {
    func testBasicFunctionality() throws {
        do {
            let res = LoginViewModel.deriveUrl(string: "file://paperless.example.com")
            XCTAssertNil(res)
        }

        do {
            // implicit https scheme
            let res = LoginViewModel.deriveUrl(string: "paperless.example.com")
            XCTAssertNotNil(res)
            let (base, url) = res!

            XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/"))
        }
    }

    func testMissingHostname() throws {
        let res = LoginViewModel.deriveUrl(string: "http://")
        XCTAssertNil(res)
    }

    func testExplicitScheme() throws {
        do {
            let res = LoginViewModel.deriveUrl(string: "http://paperless.example.com")
            XCTAssertNotNil(res)
            let (base, url) = res!
            XCTAssertEqual(base, URL(string: "http://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "http://paperless.example.com/api/"))
        }

        do {
            let res = LoginViewModel.deriveUrl(string: "https://paperless.example.com")
            XCTAssertNotNil(res)
            let (base, url) = res!
            XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
            XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/"))
        }
    }

    func testSuffix() throws {
        let res = LoginViewModel.deriveUrl(string: "https://paperless.example.com", suffix: "token")
        XCTAssertNotNil(res)
        let (base, url) = res!
        XCTAssertEqual(base, URL(string: "https://paperless.example.com"))
        XCTAssertEqual(url, URL(string: "https://paperless.example.com/api/token/"))
    }
}
