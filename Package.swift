// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemSlop",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MemSlop", targets: ["MemSlop"]),
        .library(name: "MemSlopCore", targets: ["MemSlopCore"]),
    ],
    targets: [
        .target(name: "MemSlopCore"),
        .executableTarget(
            name: "MemSlop",
            dependencies: ["MemSlopCore"]
        ),
        .testTarget(
            name: "MemSlopCoreTests",
            dependencies: ["MemSlopCore"]
        ),
    ]
)
