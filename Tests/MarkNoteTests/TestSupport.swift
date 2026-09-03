import XCTest
import Foundation
@testable import MarkNote

/// 测试共享：临时目录 + NotesStore 工厂
/// 注意：NotesStore 通过 UserDefaults("notesDirURL") 读目录，测试前必须设置。
enum TestEnv {
    @MainActor
    static func makeStore() throws -> (NotesStore, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("marknote-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 测试隔离：清掉全局域的持久化键（否则真实 app 的历史设置会污染断言）
        for key in ["notesDirURL", "sortMode", "editorMode", "theme", "editorFontSize", "editorFontFamily", "previewFontScale", "previewFont", "groupByCategory"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(dir.path, forKey: "notesDirURL")
        return (NotesStore(), dir)
    }

    /// 泵主运行循环：让 reloadIndex 的 ioQueue → main.async 回调落地
    @MainActor
    static func pump(_ seconds: Double = 0.3) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    @MainActor
    static func readNoteFile(_ store: NotesStore, _ id: String) throws -> Note? {
        let url = store.noteURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try? JSONDecoder().decode(Note.self, from: data)
    }
}
