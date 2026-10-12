import Foundation

/// 手动更新（本地仓库）—— 针对这台开发机上的迭代场景：
/// 菜单「检查更新」→ 比对当前构建与本地仓库 → 有更新就退出 → 后台重建并替换安装 → 自动重启。
///
/// 构建时 `build-app.sh` 会把 `build-info.json` 打进 App（提交号 / 构建时间 / 仓库路径），
/// 更新源就是这份仓库：仓库里有什么（含未提交改动）就重建什么 —— 不用再手动"重新安装"。
enum AppUpdater {
    struct BuildInfo: Codable {
        let gitSHA: String
        let builtAt: String
        let dirty: Bool
        let repoPath: String
    }

    enum Outcome {
        case upToDate(sha: String)
        case updating(from: String, to: String)
        case notConfigured(String)   // 没有 build-info / 仓库不可用 → 如实说明
        case failed(String)
    }

    /// "有没有新东西"：提交号不同，或工作树有未提交改动（改 bug 的间隙里也算）
    static func needsUpdate(buildSHA: String, repoHead: String, repoDirty: Bool) -> Bool {
        buildSHA != repoHead || repoDirty
    }

    static func buildInfo() -> BuildInfo? {
        guard let url = Bundle.main.url(forResource: "build-info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode(BuildInfo.self, from: data) else { return nil }
        return info
    }

    /// 手动检查 +（有更新时）启动"退出 → 重建 → 重启"流程。必须在主线程调用。
    static func checkAndUpdate() -> Outcome {
        guard let info = buildInfo() else {
            return .notConfigured(_L("这一份不是从本地仓库构建的（缺 build-info），无法用本地更新",
                                     "This copy wasn't built from the local repo — local update unavailable"))
        }
        let repo = URL(fileURLWithPath: info.repoPath)
        guard FileManager.default.fileExists(atPath: repo.appendingPathComponent("scripts/build-app.sh").path) else {
            return .notConfigured(_L("本地仓库找不到：\(info.repoPath)", "Local repo not found: \(info.repoPath)"))
        }
        guard let head = git(["rev-parse", "--short", "HEAD"], in: repo) else {
            return .failed(_L("读取仓库状态失败（git 不可用？）", "Failed to read repo state (git unavailable?)"))
        }
        let dirty = !(git(["status", "--porcelain"], in: repo) ?? "").trimmed.isEmpty
        guard needsUpdate(buildSHA: info.gitSHA, repoHead: head.trimmed, repoDirty: dirty) else {
            return .upToDate(sha: info.gitSHA)
        }
        do {
            try launchUpdateScript(repo: repo)
        } catch {
            return .failed(_L("启动更新脚本失败：\(error.localizedDescription)",
                              "Failed to launch updater: \(error.localizedDescription)"))
        }
        return .updating(from: info.gitSHA, to: head.trimmed + (dirty ? "+" : ""))
    }

    // MARK: - 内部

    private static func git(_ args: [String], in repo: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo.path] + args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 更新脚本正文（独立出来便于单测）：等 App 退出 → 重建 → 重新打开原位置
    static func updateScriptText(repo: URL, appPath: String) -> String {
        let logPath = NSHomeDirectory() + "/Library/Logs/随手-更新.log"
        return """
        #!/bin/bash
        # 由随手「检查更新」生成：等 App 退出 → 本地重建 → 自动重新打开（失败则仍开旧版）
        export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        sleep 0.5
        for i in $(seq 1 60); do
          pgrep -f "\(appPath)/Contents/MacOS/MarkNote" >/dev/null 2>&1 || break
          sleep 0.5
        done
        cd "\(repo.path)" || exit 1
        echo "[$(date '+%F %T')] 开始更新: $(git rev-parse --short HEAD)" >> "\(logPath)"
        ./scripts/build-app.sh >> "\(logPath)" 2>&1
        if [ $? -eq 0 ]; then
          echo "[$(date '+%F %T')] 更新完成" >> "\(logPath)"
        else
          echo "[$(date '+%F %T')] 更新失败，保留旧版本" >> "\(logPath)"
        fi
        open "\(appPath)"
        """
    }

    private static func launchUpdateScript(repo: URL) throws {
        let scriptPath = NSTemporaryDirectory() + "marknote-update.sh"
        try updateScriptText(repo: repo, appPath: Bundle.main.bundleURL.path)
            .write(toFile: scriptPath, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "nohup /bin/bash \"\(scriptPath)\" >/dev/null 2>&1 &"]
        try p.run()
    }
}
