// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
  name: "Common",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
  ],
  products: [
    .library(
      name: "Common",
      targets: ["Common"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/swiftlang/swift-syntax", exact: "602.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-macro-testing", from: "0.6.4"),
    .package(url: "https://github.com/SwiftyLab/MetaCodable", exact: "1.6.0"),
  ],
  targets: [
    .macro(
      name: "CommonMacros",
      dependencies: [
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
        .product(name: "SwiftBasicFormat", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "Common",
      dependencies: [
        "CommonMacros",
        .product(name: "MetaCodable", package: "MetaCodable"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "CommonTests",
      dependencies: [
        "Common",
        "CommonMacros",
        .product(name: "MacroTesting", package: "swift-macro-testing"),
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
      ]
    ),
  ]
)
