// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "Networking",
  platforms: [
    .iOS(.v17),
    .macOS(.v13),
  ],
  products: [
    // Products define the executables and libraries a package produces, making them visible to other packages.
    .library(
      name: "Networking",
      targets: ["Networking"]
    )
  ],
  dependencies: [
    .package(path: "../Common"),
    .package(path: "../DataModel"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.4"),
    .package(url: "https://github.com/groue/Semaphore", from: "0.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths", from: "1.7.1"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .target(
      name: "Networking",
      dependencies: [
        // Desperate workaround for linker error?
        .product(name: "CasePaths", package: "swift-case-paths"),
        .product(name: "Common", package: "Common"),
        .product(name: "DataModel", package: "DataModel"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
        .product(name: "Semaphore", package: "Semaphore"),
      ],
      path: "Sources",
      swiftSettings: [
        .swiftLanguageMode(.v6),
        .enableExperimentalFeature("StrictConcurrency"),
      ]
    ),
    .testTarget(
      name: "NetworkingTests",
      dependencies: ["Networking"]
    ),
  ]
)
