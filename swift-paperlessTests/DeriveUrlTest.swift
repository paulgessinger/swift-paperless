import Foundation
import Testing

@Suite("DeriveUrl") struct DeriveUrlTests {
    @Test
    func testBasicFunctionality() throws {
        // implicit https scheme
        let (base, url) = try deriveUrl(string: "paperless.example.com")

        #expect(base == URL(string: "https://paperless.example.com"))
        #expect(url == URL(string: "https://paperless.example.com/api/"))
    }

    @Test
    func testMissingHostname() throws {
        #expect(throws: UrlError.emptyHost) {
            _ = try deriveUrl(string: "http://")
        }
    }

    @Test
    func testExplicitScheme() throws {
        #expect(throws: UrlError.invalidScheme("file")) {
            _ = try deriveUrl(string: "file://paperless.example.com")
        }

        var (base, url) = try deriveUrl(string: "http://paperless.example.com")
        #expect(base == URL(string: "http://paperless.example.com"))
        #expect(url == URL(string: "http://paperless.example.com/api/"))

        (base, url) = try deriveUrl(string: "https://paperless.example.com")
        #expect(base == URL(string: "https://paperless.example.com"))
        #expect(url == URL(string: "https://paperless.example.com/api/"))
    }

    @Test
    func testSuffix() throws {
        let (base, url) = try deriveUrl(string: "https://paperless.example.com", suffix: "token")
        #expect(base == URL(string: "https://paperless.example.com"))
        #expect(url == URL(string: "https://paperless.example.com/api/token/"))
    }
}
