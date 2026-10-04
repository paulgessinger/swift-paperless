// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "AppViews",
  defaultLocalization: "en",
  // iOS-only: SwiftUI/UIKit/VisionKit views with no macOS equivalent. Logic that
  // needs tests belongs in AppShared, which builds on the host.
  platforms: [
    .iOS(.v17)
  ],
  products: [
    .library(
      name: "AppViews",
      targets: ["AppViews"]
    )
  ],
  dependencies: [
    .package(path: "../AppShared"),
    .package(path: "../Common"),
    .package(path: "../DataModel"),
    .package(path: "../Networking"),
    .package(path: "../Persistence"),
    .package(url: "https://github.com/kean/Nuke", .upToNextMajor(from: "12.0.0")),
    .package(url: "https://github.com/sunghyun-k/swiftui-toasts", .upToNextMajor(from: "1.1.0")),
    .package(
      url: "https://github.com/sunghyun-k/swiftui-window-overlay",
      .upToNextMajor(from: "1.0.0")),
  ],
  targets: [
    .target(
      name: "AppViews",
      dependencies: [
        .product(name: "AppShared", package: "AppShared"),
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
        .product(name: "Networking", package: "Networking"),
        .product(name: "Persistence", package: "Persistence"),
        .product(name: "Nuke", package: "Nuke"),
        .product(name: "NukeUI", package: "Nuke"),
        .product(name: "Toasts", package: "swiftui-toasts"),
        .product(name: "WindowOverlay", package: "swiftui-window-overlay"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    )
  ]
)
