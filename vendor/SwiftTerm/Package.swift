// swift-tools-version:5.9
//
// 随手内置的 SwiftTerm 副本（vendor）—— 只保留终端模拟器库本体：
// 去掉原仓库的 demo / fuzz / benchmark 可执行目标与 swift-argument-parser 依赖，
// 这样 `swift build` 不需要联网拉依赖。上游：https://github.com/migueldeicaza/SwiftTerm
// 版本：v1.8.0（MIT，见 LICENSE）
import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [.macOS(.v12), .iOS(.v13)],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"]),
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            dependencies: [],
            path: "Sources/SwiftTerm"
        ),
    ]
)
