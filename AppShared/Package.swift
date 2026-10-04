// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AppShared",
  defaultLocalization: "en",
  // Builds for macOS so the package can be tested on the host via
  // `swift test`; views and UIKit-dependent code live in AppViews.
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "AppShared",
      targets: ["AppShared"]
    )
  ],
  dependencies: [
    .package(path: "../Common"),
    .package(path: "../DataModel"),
    .package(path: "../Networking"),
    .package(path: "../Persistence"),
    .package(url: "https://github.com/kean/Nuke", .upToNextMajor(from: "12.0.0")),
    .package(url: "https://github.com/groue/Semaphore", .upToNextMajor(from: "0.1.0")),
    .package(
      url: "https://github.com/liamnichols/xcstrings-tool-plugin", .upToNextMajor(from: "1.2.0")),
  ],
  targets: [
    .target(
      name: "AppShared",
      dependencies: [
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
        .product(name: "Networking", package: "Networking"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "Semaphore", package: "Semaphore"),
      ],
      resources: [
        .process("Resources/Localization")
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ],
      plugins: [
        .plugin(name: "XCStringsToolPlugin", package: "xcstrings-tool-plugin")
      ]
    ),
    .testTarget(
      name: "AppSharedTests",
      dependencies: [
        "AppShared",
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
        .product(name: "Networking", package: "Networking"),
        .product(name: "Persistence", package: "Persistence"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
