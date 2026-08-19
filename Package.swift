// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Alisa",
    platforms: [
        .iOS(.v17),
    ],
    products: [
        .library(name: "AlisaCore", targets: ["AlisaCore"]),
        .library(name: "AlisaUI", targets: ["AlisaUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0"),
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
        .package(url: "https://github.com/swisspol/GCDWebServer.git", from: "3.5.4"),
        .package(url: "https://github.com/raspu/Highlightr.git", from: "2.1.0"),
    ],
    targets: [
        .target(
            name: "AlisaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "ZIPFoundation", package: "ZIPFoundation"),
                .product(name: "GCDWebServer", package: "GCDWebServer"),
            ],
            path: "Sources/Core"
        ),
        .target(
            name: "AlisaUI",
            dependencies: [
                "AlisaCore",
                .product(name: "Highlightr", package: "Highlightr"),
            ],
            path: "Sources/UI"
        ),
    ]
)