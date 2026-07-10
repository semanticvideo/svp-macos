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
            name: "CBlake3",
            path: "Sources/CBlake3",
            exclude: ["LICENSE_A2", "LICENSE_CC0", "README.md"],
            publicHeadersPath: "include",
            cSettings: [
                .define("BLAKE3_NO_SSE2"), .define("BLAKE3_NO_SSE41"),
                .define("BLAKE3_NO_AVX2"), .define("BLAKE3_NO_AVX512"),
                .define("BLAKE3_USE_NEON", to: "0")
            ]
        ),
        .target(
            name: "SVPReader",
            dependencies: ["CZlib", "CBlake3"],
            path: "Sources/SVPReader"
        ),
        .testTarget(
            name: "SVPReaderTests",
            dependencies: ["SVPReader"],
            path: "Tests/SVPReaderTests"
        ),
    ]
)
