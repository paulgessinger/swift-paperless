// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "DataModel",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "DataModel",
      targets: ["DataModel"]
    )
  ],
  dependencies: [
    .package(path: "../Common"),
    .package(
      url: "https://github.com/qizh/MetaCodable",
      revision: "44558a51537794a3eb59639048f2073aaed4c7e5"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", exact: "1.7.1"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "DataModel",
      dependencies: [
        .product(name: "Common", package: "Common"),
        .product(name: "MetaCodable", package: "MetaCodable"),
        .product(name: "CasePaths", package: "swift-case-paths"),
      ],
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "DataModelTests",
      dependencies: ["DataModel"],
      resources: [
        .copy("Data")
      ]
    ),
  ]
)
