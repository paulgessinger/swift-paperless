import Foundation
import Testing

@testable import Networking

@Suite("CSRF token for session-authenticated requests")
struct CSRFTokenTest {
  private func storage(with cookie: [HTTPCookiePropertyKey: Any]?) -> HTTPCookieStorage {
    let storage = HTTPCookieStorage.sharedCookieStorage(
      forGroupContainerIdentifier: "csrf-test-\(UUID().uuidString)")
    if let cookie, let httpCookie = HTTPCookie(properties: cookie) {
      storage.setCookie(httpCookie)
    }
    return storage
  }

  @Test(
    "Copies the csrftoken cookie into X-CSRFToken and sets a same-origin Referer",
    .bug("https://github.com/paulgessinger/swift-paperless/issues/915", id: 915))
  func addsHeaders() throws {
    let cookies = storage(with: [
      .name: "csrftoken", .value: "abc123", .domain: "paperless.example.com", .path: "/",
    ])
    var request = URLRequest(
      url: try #require(
        URL(string: "https://paperless.example.com:8443/api/documents/post_document/")))

    ApiRepository.addCSRFTokenTo(request: &request, cookies: cookies)

    #expect(request.value(forHTTPHeaderField: "X-CSRFToken") == "abc123")
    #expect(request.value(forHTTPHeaderField: "Referer") == "https://paperless.example.com:8443/")
  }

  @Test("Leaves the request alone without a csrftoken cookie")
  func noCookie() throws {
    var request = URLRequest(
      url: try #require(URL(string: "https://paperless.example.com/api/documents/post_document/")))

    ApiRepository.addCSRFTokenTo(request: &request, cookies: storage(with: nil))

    #expect(request.value(forHTTPHeaderField: "X-CSRFToken") == nil)
    #expect(request.value(forHTTPHeaderField: "Referer") == nil)
  }
}
