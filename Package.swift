// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NXNStudio",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "NXNStudio",
            path: "Sources/NXNStudio",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "NXNStudioTests",
            dependencies: ["NXNStudio"],
            path: "Tests/NXNStudioTests"
        ),
    ]
)
