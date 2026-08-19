// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alisa",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AlisaCore", targets: ["AlisaCore"]),
        .library(name: "AlisaUI", targets: ["AlisaUI"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/swisspol/GCDWebServer.git", from: "3.5.4"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/realm/SwiftLint.git", from: "0.55.0"),
    ],
    targets: [
        .target(
            name: "AlisaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
            ],
            path: "Sources/Core"
        ),
        .target(
            name: "AlisaUI",
            dependencies: [
                "AlisaCore",
                .product(name: "Highlightr", package: "Highlightr"),
                .product(name: "GCDWebServer", package: "GCDWebServer"),
            ],
            path: "Sources/UI"
        ),
        .executableTarget(
            name: "Alisa",
            dependencies: ["AlisaCore", "AlisaUI"],
            path: "Sources/App"
        ),
        .testTarget(
            name: "AlisaCoreTests",
            dependencies: ["AlisaCore"],
            path: "Tests/Unit"
        ),
        .testTarget(
            name: "AlisaIntegrationTests",
            dependencies: ["AlisaCore", "AlisaUI"],
            path: "Tests/Integration"
        ),
    ]
)