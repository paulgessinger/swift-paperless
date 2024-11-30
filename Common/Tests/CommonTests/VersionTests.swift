//
//  VersionTests.swift
//  Common
//
//  Created by Paul Gessinger on 30.11.2024.
//

@testable import Common
import Foundation
import Testing

@Suite
struct VersionTests {
    @Test
    func constructFromString() {
        #expect(Version("1.0.0") == .init(major: 1, minor: 0, patch: 0))
        #expect(Version("1.0.1") == .init(major: 1, minor: 0, patch: 1))
        #expect(Version("1.") == nil)
        #expect(Version("1.0") == nil)
        #expect(Version(".0.1.2") == nil)
        #expect(Version(".1.2") == nil)
    }

    @Test
    func convertToString() {
        #expect("\(Version(1, 2, 3))" == "1.2.3")

        #expect(String(describing: Version(4, 5, 6)) == "4.5.6")
    }

    @Test
    func access() {
        let version = Version(1, 2, 3)
        #expect(version.major == 1)
        #expect(version.minor == 2)
        #expect(version.patch == 3)

        let version2 = Version(major: 1, minor: 2, patch: 3)
        #expect(version2.major == 1)
        #expect(version2.minor == 2)
        #expect(version2.patch == 3)
    }

    @Test
    func comparable() {
        #expect(Version(0, 0, 1) < Version(0, 0, 2))
        #expect(Version(0, 1, 0) < Version(0, 9, 0))
        #expect(Version(1, 0, 0) < Version(2, 0, 0))

        #expect(Version(0, 0, 1) <= Version(0, 0, 2))
        #expect(Version(0, 1, 0) >= Version(0, 0, 9))
        #expect(Version(1, 0, 0) >= Version(0, 9, 9))

        #expect(Version(0, 0, 2) > Version(0, 0, 1))
        #expect(Version(0, 0, 9) < Version(0, 1, 0))
        #expect(Version(0, 9, 9) < Version(1, 0, 0))

        #expect(Version(0, 0, 2) >= Version(0, 0, 1))

        #expect(Version(1, 0, 0) <= Version(1, 0, 0))
        #expect(Version(1, 0, 0) >= Version(1, 0, 0))
    }
}
