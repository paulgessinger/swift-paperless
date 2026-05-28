// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Persistence",
  // Cross-platform so the schema, record, and importer tests are host-runnable
  // on macOS via `swift test --package-path Persistence`. Production consumer
  // is iOS-only (AppShared).
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "Persistence",
      targets: ["Persistence"]
    )
  ],
  dependencies: [
    .package(path: "../Common"),
    .package(path: "../DataModel"),
    .package(url: "https://github.com/groue/GRDB.swift", .upToNextMajor(from: "7.0.0")),
  ],
  targets: [
    .target(
      name: "Persistence",
      dependencies: [
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
        .product(name: "GRDB", package: "GRDB.swift"),
      ],
      path: "Sources/Persistence",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "PersistenceTests",
      dependencies: [
        "Persistence",
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
      ],
      path: "Tests/PersistenceTests"
    ),
  ]
)
