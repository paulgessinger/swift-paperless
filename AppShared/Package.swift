// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AppShared",
  defaultLocalization: "en",
  // iOS-only: AppShared bundles SwiftUI/UIKit/VisionKit UI code that has no
  // macOS equivalent. Logic-only tests therefore run on the iOS simulator.
  platforms: [
    .iOS(.v17)
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
    .package(url: "https://github.com/kean/Nuke", .upToNextMajor(from: "12.0.0")),
    .package(
      url: "https://github.com/gonzalezreal/swift-markdown-ui.git",
      .upToNextMajor(from: "2.3.1")),
    .package(url: "https://github.com/groue/Semaphore", .upToNextMajor(from: "0.1.0")),
    .package(
      url: "https://github.com/apple/swift-async-algorithms", .upToNextMajor(from: "1.0.0")),
    .package(url: "https://github.com/markbattistella/BezelKit", .upToNextMajor(from: "4.1.1")),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.2"),
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
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "NukeExtensions", package: "Nuke"),
        .product(name: "MarkdownUI", package: "swift-markdown-ui"),
        .product(name: "Semaphore", package: "Semaphore"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "BezelKit", package: "BezelKit"),
        .product(name: "CasePaths", package: "swift-case-paths"),
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
    )
  ]
)
