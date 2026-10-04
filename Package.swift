// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MarkNote",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 内置终端：完整 xterm 终端模拟器（VS Code 那边的终端体验同源思路），MIT 许可。
        // 用 vendor 副本而不是远端依赖：swift build 不需要联网，构建可复现。
        .package(path: "vendor/SwiftTerm"),
    ],
    targets: [
        .executableTarget(
            name: "MarkNote",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
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
