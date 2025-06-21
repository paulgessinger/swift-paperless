import DataModel
import Foundation
import Testing

@testable import Networking

@Suite struct RequestErrorTest {
    @Test func testUnexpectedStatusCodeFactory() throws {
        // Test with valid UTF-8 data
        let validData = "Error message".data(using: .utf8)!
        let error = RequestError.unexpectedStatusCode(code: .internalServerError, body: validData)

        #expect(error == .unexpectedStatusCode(code: .internalServerError, detail: "Error message"))

        // Test with invalid UTF-8 data
        let invalidData = Data([0xFF, 0xFE, 0xFD]) // Invalid UTF-8 bytes
        let error2 = RequestError.unexpectedStatusCode(code: .badRequest, body: invalidData)

        #expect(error2 == .unexpectedStatusCode(code: .badRequest, detail: "[NO BODY]"))

        // Test with empty data
        let emptyData = Data()
        let error3 = RequestError.unexpectedStatusCode(code: .notFound, body: emptyData)

        #expect(error3 == .unexpectedStatusCode(code: .notFound, detail: ""))
    }

    @Test func testExtractErrorMessageFromResponseBody() throws {
        let responseBody = """
        {"custom_fields":[{},{},{},{},{"non_field_errors":["Unable to parse URI j, missing scheme"]},{},{},{},{},{}]}
        """.data(using: .utf8)!

        let error = RequestError.unexpectedStatusCode(code: .badRequest, body: responseBody)
        #expect(
            error
                == .unexpectedStatusCode(
                    code: .badRequest, detail: "Unable to parse URI j, missing scheme"
                ))
    }

    @Test func testExtractErrorMessageWithDifferentTopLevelKey() throws {
        let responseBody = """
        {"some_other_key":[{},{},{},{},{"non_field_errors":["Different error message"]},{},{},{},{},{}]}
        """.data(using: .utf8)!

        let error = RequestError.unexpectedStatusCode(code: .badRequest, body: responseBody)
        #expect(
            error == .unexpectedStatusCode(code: .badRequest, detail: "Different error message"))
    }

    @Test func testExtractErrorMessageWithNoNonFieldErrors() throws {
        let responseBody = """
        {"custom_fields":[{},{},{},{},{},{},{},{},{},{}]}
        """.data(using: .utf8)!

        let error = RequestError.unexpectedStatusCode(code: .badRequest, body: responseBody)
        #expect(
            error
                == .unexpectedStatusCode(
                    code: .badRequest, detail: "{\"custom_fields\":[{},{},{},{},{},{},{},{},{},{}]}"
                ))
    }

    @Test func testExtractErrorMessageWithMultipleNonFieldErrors() throws {
        let responseBody = """
        {"custom_fields":[{},{},{},{},{"non_field_errors":["First error", "Second error"]},{},{},{},{},{}]}
        """.data(using: .utf8)!

        let error = RequestError.unexpectedStatusCode(code: .badRequest, body: responseBody)
        #expect(
            error
                == .unexpectedStatusCode(
                    code: .badRequest, detail: "1. First error\n2. Second error"
                ))
    }

    @Test func testExtractErrorMessageWithDetailField() throws {
        let responseBody = """
        {"detail": "Error message here"}
        """.data(using: .utf8)!

        let error = RequestError.unexpectedStatusCode(code: .badRequest, body: responseBody)
        #expect(error == .unexpectedStatusCode(code: .badRequest, detail: "Error message here"))
    }

    @Test func testForbiddenFactory() throws {
        let responseBody = """
        {"detail": "Access denied"}
        """.data(using: .utf8)!

        let error = RequestError.forbidden(body: responseBody)
        #expect(error == .forbidden(detail: "Access denied"))
    }

    @Test func testUnauthorizedFactory() throws {
        let responseBody = """
        {"detail": "Authentication required"}
        """.data(using: .utf8)!

        let error = RequestError.unauthorized(body: responseBody)
        #expect(error == .unauthorized(detail: "Authentication required"))
    }
}
