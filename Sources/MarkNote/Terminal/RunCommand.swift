import Foundation

/// 「运行当前文件」的命令解析：扩展名 → 解释器/编译器命令。
/// 只做字符串拼装（可单测），实际执行交给 TerminalSession。
enum RunCommand {

    /// 编译型语言的临时产物目录（源码旁不留垃圾）
    static var buildDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("marknote-run", isDirectory: true)
    }

    /// 工作台配置 + 项目识别的运行命令（IDE 式）：
    /// - 自定义命令（run.json 里的 commands）优先
    /// - C/C++：带上工作台声明的第三方库（pkg-config）+ Homebrew 头文件/库路径
    /// - Python：优先用工作台里的 .venv
    /// - CMake / Makefile / npm / Go / Cargo 项目：交给项目自己的构建方式
    static func command(forExt ext: String, file: String, workspace: URL? = nil,
                        buildDir: URL = RunCommand.buildDir) -> String? {
        let fileURL = URL(fileURLWithPath: file)
        let ws = workspace ?? fileURL.deletingLastPathComponent()
        let config = RunConfig.load(from: ws)
        let project = ProjectKind.detect(from: fileURL, workspace: ws)
        let path = shellQuote(file)
        let dir = shellQuote(fileURL.deletingLastPathComponent().path)

        // 1) 工作台自定义命令：完全按用户写的来
        if let custom = config.commands[ext.lowercased()], !custom.isEmpty {
            return substitute(custom, file: file, dir: fileURL.deletingLastPathComponent().path)
        }

        switch (project.kind, ext.lowercased()) {
        case (.cmake, _):
            let root = shellQuote(project.root.path)
            return "cd \(root) && (cmake -S . -B build -DCMAKE_BUILD_TYPE=Release >/dev/null && cmake --build build -j) "
                + "&& (test -f build/\(shellQuote(stem(fileURL))) && ./build/\(shellQuote(stem(fileURL))) || true)"
        case (.make, _):
            return "cd \(shellQuote(project.root.path)) && make"
        case (.rust, _):
            return "cd \(shellQuote(project.root.path)) && cargo run"
        case (.go, _):
            return "cd \(shellQuote(project.root.path)) && go run ."
        case (.node, let e) where ["js", "mjs", "cjs", "ts", "tsx", "jsx"].contains(e):
            return "cd \(shellQuote(project.root.path)) && (test -f package.json && "
                + "node -e 'const s=require(\"./package.json\").scripts||{};process.exit(s.start?0:1)' "
                + "&& npm start || node \(shellQuote(fileURL.path)))"
        default:
            break
        }

        return singleFileCommand(forExt: ext, file: file, fileURL: fileURL, dir: dir, path: path,
                                 config: config, buildDir: buildDir)
    }

    /// 单文件模式（没有项目文件时）：按语言挑解释器/编译器，并把第三方库带上
    private static func singleFileCommand(forExt ext: String, file: String, fileURL: URL, dir: String,
                                          path: String, config: RunConfig, buildDir: URL) -> String? {
        let path = shellQuote(file)
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let out = shellQuote(buildDir.appendingPathComponent(stem.isEmpty ? "a.out" : stem).path)
        // 第三方库：pkg-config（装了 brew 的库基本都能被它找到）+ Homebrew 头文件/库目录兜底
        let brew = "/opt/homebrew"
        let pkg = config.libs.isEmpty ? "" :
            "$(pkg-config --cflags --libs \(config.libs.map(shellQuote).joined(separator: " ")) 2>/dev/null)"
        let extra = (config.cxxFlags + config.linkFlags).joined(separator: " ")
        let cxxExtra = ["-I\(brew)/include", "-L\(brew)/lib", extra, pkg]
            .filter { !$0.isEmpty }.joined(separator: " ")
        switch ext.lowercased() {
        case "py", "pyw", "pyi":
            // 工作台里有虚拟环境就用它（IDE 的 interpreter 概念），否则用系统 python3
            if let custom = config.python, !custom.isEmpty { return "\(shellQuote(custom)) \(path)" }
            let venv = fileURL.deletingLastPathComponent().appendingPathComponent(".venv/bin/python").path
            return "test -x \(shellQuote(venv)) && \(shellQuote(venv)) \(path) || python3 \(path)"
        case "js", "mjs", "cjs":
            return "node \(path)"
        case "jsx", "ts", "tsx", "mts", "cts":
            // 有 tsx 用 tsx（支持 TS/JSX），否则退回 node（Node 22+ 可直跑 TS 单文件）
            return "command -v tsx >/dev/null 2>&1 && tsx \(path) || node \(path)"
        case "go":
            return "go run \(path)"
        case "rs":
            return "command -v cargo >/dev/null 2>&1 && (cargo run -q --manifest-path \"$(dirname \(path))/Cargo.toml\" 2>/dev/null || rustc \(path) -o \(out) && \(out)) || (rustc \(path) -o \(out) && \(out))"
        case "c", "h":
            return "mkdir -p \(shellQuote(buildDir.path)) && clang \(path) \(cxxExtra) -o \(out) && \(out)"
        case "cpp", "cc", "cxx", "c++", "hpp", "hh":
            let std = config.cxxFlags.contains(where: { $0.hasPrefix("-std=") }) ? "" : "-std=c++17 -O2"
            return "mkdir -p \(shellQuote(buildDir.path)) && c++ \(std) \(path) \(cxxExtra) -o \(out) && \(out)"
        case "cs":
            return "command -v dotnet >/dev/null 2>&1 && dotnet run --project \"$(dirname \(path))\" || echo '需要 dotnet SDK'"
        case "java":
            return "java \(path)"
        case "kt", "kts":
            return "command -v kotlinc >/dev/null 2>&1 && kotlinc -script \(path) || echo '需要 kotlinc'"
        case "swift":
            return "swift \(path)"
        case "rb":
            return "ruby \(path)"
        case "php":
            return "php \(path)"
        case "lua":
            return "lua \(path)"
        case "pl", "pm":
            return "perl \(path)"
        case "sh":
            return "/bin/sh \(path)"
        case "bash":
            return "/bin/bash \(path)"
        case "zsh":
            return "/bin/zsh \(path)"
        case "fish":
            return "fish \(path)"
        case "html", "htm", "xhtml":
            return "open \(path)"          // 网页：交给默认浏览器，不在终端里刷标签
        case "sql":
            return "sqlite3 \(path)"
        case "r":
            return "Rscript \(path)"
        default:
            return nil
        }
    }

    /// 自定义命令占位符：{file} {dir} {stem}
    static func substitute(_ template: String, file: String, dir: String) -> String {
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        return template
            .replacingOccurrences(of: "{file}", with: shellQuote(file))
            .replacingOccurrences(of: "{dir}", with: shellQuote(dir))
            .replacingOccurrences(of: "{stem}", with: stem)
    }

    private static func stem(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// 单引号包裹（POSIX）：路径里有空格、引号、$ 都安全
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
