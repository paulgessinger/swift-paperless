//
//  Version.swift
//  Common
//
//  Created by Paul Gessinger on 30.11.2024.
//

public
struct Version: LosslessStringConvertible, Equatable, Comparable, Sendable {
    let major: UInt
    let minor: UInt
    let patch: UInt

    public init?(_ value: String) {
        let components = value.components(separatedBy: ".")
        guard components.count == 3 else {
            return nil
        }

        let numbers = components.compactMap { UInt($0) }

        guard numbers.count == 3 else {
            return nil
        }

        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public init(_ major: UInt, _ minor: UInt, _ patch: UInt) {
        self.init(major: major, minor: minor, patch: patch)
    }

    public init(major: UInt, minor: UInt, patch: UInt) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public var tuple: (UInt, UInt, UInt) {
        (major, minor, patch)
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.tuple < rhs.tuple
    }
}