import Foundation

/// AI 文件代理：工具调用定义（OpenAI 兼容 function calling 格式）。
/// 能力边界：只在当前工作台（notesDir）内操作；越界/隐藏目录一律拒绝。
enum FileTools {

    /// OpenAI tools 数组（供 chat 请求使用）
    static let specs: [[String: Any]] = [
        ["type": "function", "function": [
            "name": "list_files",
            "description": _L("列出工作台目录内容（文件夹与文件，含大小/行数）。path 为空表示根目录；可传相对目录。", "List workspace directory contents (folders and files, with size/line count). An empty path means the root directory; a relative directory may be passed."),
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string", "description": _L("相对路径（可选，默认根目录）", "Relative path (optional; defaults to the root directory)")]],
                "required": [],
            ],
        ]],
        ["type": "function", "function": [
            "name": "read_file",
            "description": _L("读取工作台内文本文件内容（截断 8000 字符；二进制文件返回说明）。", "Read the contents of a text file in the workspace (truncated to 8000 characters; binary files return a note)."),
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string", "description": _L("相对路径，如 笔记/我的.md", "Relative path, e.g. notes/my.md")]],
                "required": ["path"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "write_file",
            "description": _L("写入/新建/追加工作台内文本文件（自动创建目录）。mode=create 仅新建（已存在报错）；overwrite 覆盖；append 追加。", "Write/create/append a text file in the workspace (auto-creates directories). mode=create creates only (errors if the file exists); overwrite replaces; append appends."),
            "parameters": [
                "type": "object",
                "properties": [
                    "path": ["type": "string", "description": _L("相对路径", "Relative path")],
                    "content": ["type": "string", "description": _L("完整新内容（overwrite/create）或追加片段（append）", "Full new content (overwrite/create) or the fragment to append (append)")],
                    "mode": ["type": "string", "enum": ["create", "overwrite", "append"], "description": _L("默认 overwrite", "Defaults to overwrite")],
                ],
                "required": ["path", "content"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "rename_file",
            "description": _L("重命名工作台内文件（同目录内改文件名/扩展名）。", "Rename a file in the workspace (change the file name/extension within the same directory)."),
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string"], "newName": ["type": "string", "description": _L("新文件名（含扩展名）", "New file name (including extension)")]],
                "required": ["path", "newName"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "move_file",
            "description": _L("把文件移动到工作台内另一个文件夹（自动创建目标目录；目标同名会失败）。", "Move a file to another folder in the workspace (auto-creates the destination directory; fails if a file with the target name already exists)."),
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string"], "folder": ["type": "string", "description": _L("目标相对文件夹，空=根目录", "Destination relative folder; empty = root directory")]],
                "required": ["path", "folder"],
            ],
        ]],
        ["type": "function", "function": [
            "name": "delete_file",
            "description": _L("删除工作台内文件（移入 .trash，可从 Finder 找回；执行前需要用户确认）。", "Delete a file in the workspace (moved to .trash and recoverable from Finder; requires user confirmation first)."),
            "parameters": [
                "type": "object",
                "properties": ["path": ["type": "string"]],
                "required": ["path"],
            ],
        ]],
    ]

    /// 解析后的单次工具调用
    struct ParsedCall: Identifiable {
        let id: String
        let name: String
        let arguments: String
        var argsDict: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]) ?? [:]
        }
    }

    /// 工具展示事件（对话流里的留痕 chip）
    struct Event: Identifiable {
        let id: String
        let icon: String
        let title: String
    }

    /// 需要用户确认的破坏性操作（delete_file）
    struct PendingConfirm: Identifiable {
        let id: String
        let call: ParsedCall
        var title: String
    }
}
