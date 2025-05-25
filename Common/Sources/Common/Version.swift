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

public
struct AppVersion: CustomStringConvertible, Codable {
    public let version: Version
    public let build: UInt

    private enum CodingKeys: String, CodingKey {
        case release, build
    }

    public init(version: Version, build: UInt) {
        self.version = version
        self.build = build
    }

    public init?(version: String, build: String) {
        guard let version = Version(version) else {
            return nil
        }

        guard let build = UInt(build) else {
            return nil
        }

        self.init(version: version, build: build)
    }

    public init?(release: [UInt], build: String) {
        guard let build = UInt(build) else {
            return nil
        }
        self.init(version: Version(major: release[0], minor: release[1], patch: release[2]), build: build)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let release = try container.decode([UInt].self, forKey: .release)
        guard release.count == 3 else {
            throw DecodingError.dataCorruptedError(forKey: .release, in: container, debugDescription: "Version must have exactly 3 components")
        }
        version = Version(major: release[0], minor: release[1], patch: release[2])
        build = try container.decode(UInt.self, forKey: .build)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([version.major, version.minor, version.patch], forKey: .release)
        try container.encode(build, forKey: .build)
    }

    public var description: String {
        "\(version) (\(build))"
    }
}
