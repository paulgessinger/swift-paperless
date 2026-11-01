// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Scanning",
  // Cross-platform so the transport merge, capability mapping and scan-request
  // translation are host-runnable on macOS via `swift test --package-path
  // Scanning`. Production consumer is the iOS app target.
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
  ],
  products: [
    .library(
      name: "Scanning",
      targets: ["Scanning"]
    )
  ],
  dependencies: [
    // Pinned to the minor: upstream has shipped four majors in twelve months,
    // and 4.0.0's own release notes disown it. Nothing outside this package
    // imports SwiftESCL, so replacing or vendoring it stays a local change.
    .package(url: "https://github.com/LeoKlaus/SwiftESCL", .upToNextMinor(from: "4.1.1"))
  ],
  targets: [
    .target(
      name: "Scanning",
      dependencies: [
        .product(name: "SwiftESCL", package: "SwiftESCL")
      ],
      path: "Sources/Scanning",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "ScanningTests",
      dependencies: ["Scanning"],
      path: "Tests/ScanningTests"
    ),
  ]
)
