import Foundation

/// 「运行当前文件」的命令解析：扩展名 → 解释器/编译器命令。
/// 只做字符串拼装（可单测），实际执行交给 TerminalSession。
enum RunCommand {

    /// 编译型语言的临时产物目录（源码旁不留垃圾）
    static var buildDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("marknote-run", isDirectory: true)
    }

    /// 不支持自动运行的类型 → nil（面板里提示手动输入命令）
    static func command(forExt ext: String, file: String, buildDir: URL = RunCommand.buildDir) -> String? {
        let path = shellQuote(file)
        let stem = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        let out = shellQuote(buildDir.appendingPathComponent(stem.isEmpty ? "a.out" : stem).path)
        switch ext.lowercased() {
        case "py", "pyw", "pyi":
            return "python3 \(path)"
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
            return "mkdir -p \(shellQuote(buildDir.path)) && clang \(path) -o \(out) && \(out)"
        case "cpp", "cc", "cxx", "c++", "hpp", "hh":
            return "mkdir -p \(shellQuote(buildDir.path)) && c++ -std=c++17 -O2 \(path) -o \(out) && \(out)"
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

    /// 单引号包裹（POSIX）：路径里有空格、引号、$ 都安全
    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
