import Foundation

/// 每个工作台的运行配置 —— 相当于 IDE 里的 `tasks.json` / `c_cpp_properties.json`：
/// 让"▶ 运行当前文件"知道要带哪些包含路径、链接哪些第三方库。
///
/// 存 `工作台/.marknote/run.json`（点目录不进索引，不打扰笔记列表）。
/// 装库仍然用包管理器（brew / pip / npm / go / cargo），这里只声明"用哪个库"。
struct RunConfig: Codable, Equatable {
    /// 追加编译参数，例如 ["-std=c++20", "-O2", "-Wall"]
    var cxxFlags: [String] = []
    /// 第三方库（pkg-config 名，例如 ["fmt", "sdl2"]）→ 自动加 --cflags --libs
    var libs: [String] = []
    /// 追加链接参数，例如 ["-framework", "Cocoa"] 或 ["-lpthread"]
    var linkFlags: [String] = []
    /// 指定解释器（不填则：Python 优先用工作台里的 .venv）
    var python: String?
    /// 扩展名 → 自定义命令（支持 {file} / {dir} / {stem} 占位）
    var commands: [String: String] = [:]

    static let dirName = ".marknote"
    static let fileName = "run.json"

    static func url(in workspace: URL) -> URL {
        workspace.appendingPathComponent(dirName, isDirectory: true).appendingPathComponent(fileName)
    }

    static func load(from workspace: URL) -> RunConfig {
        let url = url(in: workspace)
        guard let data = try? Data(contentsOf: url),
              let cfg = try? JSONDecoder().decode(RunConfig.self, from: data) else { return RunConfig() }
        return cfg
    }

    func save(to workspace: URL) throws {
        let url = Self.url(in: workspace)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }

    var isEmpty: Bool { self == RunConfig() }
}

/// 工作台里"这是什么项目"的判定（决定 ▶ 用哪种构建/运行方式）
enum ProjectKind: String {
    case cmake, make, node, python, go, rust, single

    var displayName: String {
        switch self {
        case .cmake: return "CMake"
        case .make: return "Makefile"
        case .node: return "Node / npm"
        case .python: return "Python"
        case .go: return "Go module"
        case .rust: return "Cargo"
        case .single: return _L("单文件", "Single file")
        }
    }

    static func detect(in dir: URL) -> ProjectKind {
        let fm = FileManager.default
        func has(_ name: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(name).path) }
        if has("CMakeLists.txt") { return .cmake }
        if has("Makefile") || has("makefile") { return .make }
        if has("package.json") { return .node }
        if has("pyproject.toml") || has("requirements.txt") || has(".venv") { return .python }
        if has("go.mod") { return .go }
        if has("Cargo.toml") { return .rust }
        return .single
    }

    /// 往上找项目根（源码常在 src/ 子目录里）
    static func detect(from file: URL, workspace: URL) -> (kind: ProjectKind, root: URL) {
        var dir = file.deletingLastPathComponent()
        let ws = workspace.standardizedFileURL
        for _ in 0..<4 {
            let kind = detect(in: dir)
            if kind != .single { return (kind, dir) }
            if dir.standardizedFileURL.path == ws.path { break }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return (.single, file.deletingLastPathComponent())
    }
}
