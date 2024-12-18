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
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/liamnichols/xcstrings-tool-plugin.git", from: "1.0.0"),
        .package(path: "../Common"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DataModel",
            dependencies: [
                .product(name: "XCStringsToolPlugin", package: "xcstrings-tool-plugin"),
                .product(name: "Common", package: "Common"),
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
        .testTarget(
            name: "DataModelTests",
            dependencies: ["DataModel"]
        ),
    ]
)
