// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SVPReader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SVPReader", targets: ["SVPReader"]),
    ],
    targets: [
        .target(
            name: "CZlib",
            path: "Sources/CZlib",
            linkerSettings: [.linkedLibrary("z")]
        ),
        .target(
            name: "SVPReader",
            dependencies: ["CZlib"],
            path: "Sources/SVPReader"
        ),
        .testTarget(
            name: "SVPReaderTests",
            dependencies: ["SVPReader"],
            path: "Tests/SVPReaderTests"
        ),
    ]
)
