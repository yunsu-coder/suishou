// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MarkNote",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MarkNote",
            path: "Sources/MarkNote",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "MarkNoteTests",
            dependencies: ["MarkNote"]
        )
    ]
)
