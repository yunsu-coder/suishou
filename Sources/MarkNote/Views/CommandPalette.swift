import SwiftUI

/// 命令注册表 + 命令面板（Ctrl+Shift+P，VSCode 风格）
/// 1. 输入过滤；2. ↑↓ 选择；3. Enter 执行 / Esc 关闭

struct CommandItem: Identifiable {
    let id = UUID()
    /// 稳定键（用于"最近使用"计数持久化）
    let key: String
    let title: String
    let category: String   // 显示为小标签（视图/主题/文件…）
    let icon: String
    let action: () -> Void
}

/// 最近使用统计（本地持久化 UserDefaults；次数降序排前）
@MainActor
enum CommandUsage {
    private static let storeKey = "commandUsage"
    private static var dict: [String: Int] {
        (UserDefaults.standard.dictionary(forKey: storeKey) as? [String: Int]) ?? [:]
    }

    static func record(_ key: String) {
        var d = dict
        d[key] = (d[key] ?? 0) + 1
        UserDefaults.standard.set(d, forKey: storeKey)
    }

    static func count(_ key: String) -> Int {
        dict[key] ?? 0
    }
}

@MainActor
enum CommandRegistry {
    /// 构建命令表（依托当前 store 状态）
    static func commands(_ store: NotesStore) -> [CommandItem] {
        var items: [CommandItem] = []

        items.append(CommandItem(key: "file.new", title: _L("新建文件…", "New File…"), category: _L("文件", "File"), icon: "square.and.pencil") { store.createNote() })
        items.append(CommandItem(key: "file.newFolder", title: _L("新建文件夹…", "New Folder…"), category: _L("文件", "File"), icon: "folder.badge.plus") {
            NotificationCenter.default.post(name: .requestNewCategory, object: nil)
        })
        items.append(CommandItem(key: "file.importFiles", title: _L("导入文件…", "Import Files…"), category: _L("文件", "File"), icon: "square.and.arrow.down") {
            NotificationCenter.default.post(name: .requestImportFiles, object: nil)
        })
        items.append(CommandItem(key: "file.importFolder", title: _L("导入文件夹…", "Import Folder…"), category: _L("文件", "File"), icon: "folder") {
            NotificationCenter.default.post(name: .requestImportFolder, object: nil)
        })
        items.append(CommandItem(key: "file.delete", title: _L("删除选中文件（物理删除）", "Delete Selected File (Permanently)"), category: _L("文件", "File"), icon: "trash") {
            store.deleteSelection()
        })
        items.append(CommandItem(key: "file.versions", title: _L("历史版本…", "History Versions…"), category: _L("文件", "File"), icon: "clock.arrow.circlepath") {
            NotificationCenter.default.post(name: .requestVersions, object: nil)
        })
        items.append(CommandItem(key: "export.md", title: _L("导出 Markdown…", "Export Markdown…"), category: _L("导出", "Export"), icon: "square.and.arrow.up") { ExportService.exportMD(store) })
        items.append(CommandItem(key: "export.txt", title: _L("导出纯文本…", "Export Plain Text…"), category: _L("导出", "Export"), icon: "doc.plaintext") { ExportService.exportTXT(store) })
        items.append(CommandItem(key: "export.pdf", title: _L("导出 PDF…", "Export PDF…"), category: _L("导出", "Export"), icon: "doc.richtext") { ExportService.exportPDF(store) })
        items.append(CommandItem(key: "export.html", title: _L("导出 HTML…", "Export HTML…"), category: _L("导出", "Export"), icon: "globe") { ExportService.exportHTML(store) })

        items.append(CommandItem(key: "view.editor", title: _L("仅编辑", "Editor Only"), category: _L("视图", "View"), icon: "text.cursor") {
            Self.setMode(EditorMode.editor.rawValue)
        })
        items.append(CommandItem(key: "view.split", title: _L("分屏", "Split"), category: _L("视图", "View"), icon: "rectangle.split.2x1") {
            Self.setMode(EditorMode.split.rawValue)
        })
        items.append(CommandItem(key: "view.preview", title: _L("仅预览", "Preview Only"), category: _L("视图", "View"), icon: "doc.richtext") {
            Self.setMode(EditorMode.preview.rawValue)
        })


        // AI 问答 / 选中文本快捷操作
        items.append(CommandItem(key: "ai.panel", title: _L("AI 问答面板（显示/隐藏）", "AI Chat Panel (Show/Hide)"), category: _L("AI", "AI"), icon: "sparkles") {
            NotificationCenter.default.post(name: .aiPanelToggle, object: nil)
        })
        for action in AIQuickAction.allCases {
            items.append(CommandItem(key: "ai." + action.rawValue, title: _L("AI \(action.title)（选中内容）", "AI \(action.title) (Selected Text)"), category: _L("AI", "AI"), icon: action.icon) {
                NotificationCenter.default.post(name: .aiQuickActionRequested, object: action)
            })
        }

        items.append(CommandItem(key: "help.shortcuts", title: _L("查看快捷键一览…", "View Shortcuts…"), category: _L("帮助", "Help"), icon: "keyboard") {
            NSAlert.helpShortcuts()
        })

        // 插入语法（与「插入」菜单同源）
        let insertItems: [(InsertKind, String)] = [
            (.link, "link"),
            (.code, "chevron.left.forwardslash.chevron.right"),
            (.codeBlock, "curlybraces"),
            (.math, "x.squareroot"),
            (.table, "tablecells"),
            (.attachment, "paperclip"),
        ]
        for (kind, icon) in insertItems {
            items.append(CommandItem(key: "insert." + kind.rawValue, title: _L("插入：\(kind.title)", "Insert: \(kind.title)"), category: _L("插入", "Insert"), icon: icon) {
                NotificationCenter.default.post(name: .insertMarkdown, object: kind)
            })
        }

        // 插件命令（P4：白名单 action 映射到宿主动作）
        let pluginActions: [String: () -> Void] = [
            "newNote": { store.createNote() },
            "newFolder": { NotificationCenter.default.post(name: .requestNewCategory, object: nil) },
            "importFiles": { NotificationCenter.default.post(name: .requestImportFiles, object: nil) },
            "importFolder": { NotificationCenter.default.post(name: .requestImportFolder, object: nil) },
            "toggleSidebar": { NotificationCenter.default.post(name: .toggleSidebarRequested, object: nil) },
            "toggleAIPanel": { NotificationCenter.default.post(name: .aiPanelToggle, object: nil) },
            "openSettings": { NSApp.sendAction(Selector("showSettingsWindow:"), to: nil, from: nil) },
            "showVersions": { NotificationCenter.default.post(name: .requestVersions, object: nil) },
            "showQuickOpen": { NotificationCenter.default.post(name: .quickOpenRequested, object: nil) },
            "aiPanel": { NotificationCenter.default.post(name: .aiPanelToggle, object: nil) },
            "aiTranslate": { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.translate) },
            "aiRewrite": { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.rewrite) },
            "aiPolish": { NotificationCenter.default.post(name: .aiQuickActionRequested, object: AIQuickAction.polish) },
            "modeEditor": { CommandRegistry.setMode(EditorMode.editor.rawValue) },
            "modeSplit": { CommandRegistry.setMode(EditorMode.split.rawValue) },
            "modePreview": { CommandRegistry.setMode(EditorMode.preview.rawValue) },
        ]
        for c in PluginManager.shared.allCommands() {
            if let action = pluginActions[c.actionID] {
                items.append(CommandItem(key: c.id, title: c.name, category: c.category, icon: c.icon, action: action))
            }
        }
        // 插件 snippets：插入模板
        for sn in PluginManager.shared.allSnippets() where sn.language == "all" || sn.language == "markdown" || sn.language == "code" {
            items.append(CommandItem(key: "sn.\(sn.id)", title: _L("插入：\(sn.name)", "Insert: \(sn.name)"), category: _L("模板", "Template"), icon: "text.insert") {
                NotificationCenter.default.post(name: .aiInsertResult, object: sn.displayText)
            })
        }
        // 轻量设定：按特性开关过滤（隐藏禁用项）
        items = items.filter { item in
            switch item.key {
            case "export.pdf": return FeatureModules.isEnabled(FeatureModules.exportPDF)
            case "export.html": return FeatureModules.isEnabled(FeatureModules.exportHTML)
            case "ai.translate", "ai.rewrite", "ai.polish": return FeatureModules.isEnabled(FeatureModules.aiQuickActions)
            default: return true
            }
        }
        return items
    }

    static func setMode(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: "editorMode")
        NotificationCenter.default.post(name: .editorModeDidChange, object: nil)
    }
}

/// 命令面板弹层
struct CommandPalette: View {
    @Environment(NotesStore.self) private var store
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var inputFocused: Bool

    private var allCommands: [CommandItem] {
        CommandRegistry.commands(store)
    }

    private var filtered: [CommandItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        var list: [CommandItem]
        if q.isEmpty {
            list = allCommands
        } else {
            let lower = q.lowercased()
            list = allCommands.filter {
                $0.title.lowercased().contains(lower) || $0.category.lowercased().contains(lower)
            }
        }
        // 最近使用排序：次数降序；同热度保持原始顺序（稳定）
        let order = Dictionary(uniqueKeysWithValues: allCommands.enumerated().map { ($0.element.id, $0.offset) })
        list.sort { a, b in
            let ca = CommandUsage.count(a.key)
            let cb = CommandUsage.count(b.key)
            if ca != cb { return ca > cb }
            return (order[a.id] ?? 0) < (order[b.id] ?? 0)
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "command")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
                TextField(_LL("输入命令…", "Type a command…"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.return) { execute(); return .handled }
                    .onKeyPress(.escape) { isPresented = false; return .handled }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if filtered.isEmpty {
                Text(_L("没有匹配命令", "No matching commands"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(24)
            } else {
                List(selection: Binding<Int>(get: { selection }, set: { selection = $0 })) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { index, cmd in
                        CommandRow(item: cmd, selected: index == selection)
                            .tag(index)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selection = index
                                CommandUsage.record(cmd.key)
                                cmd.action()
                                isPresented = false
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(maxHeight: 320)
            }
        }
        .frame(width: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(nsColor: .separatorColor), lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .padding(.top, 48)
        .onAppear {
            DispatchQueue.main.async { inputFocused = true }
            selection = 0
        }
    }

    private func move(_ d: Int) {
        guard !filtered.isEmpty else { return }
        selection = (selection + d + filtered.count) % filtered.count
    }

    private func execute() {
        guard filtered.indices.contains(selection) else { return }
        CommandUsage.record(filtered[selection].key)
        filtered[selection].action()
        isPresented = false
    }
}

private struct CommandRow: View {
    let item: CommandItem
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 18)
            Text(item.title)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            let count = CommandUsage.count(item.key)
            if count > 0 {
                Text("×\(count)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            Text(item.category)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.14) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
    }
}

private extension NSAlert {
    static func helpShortcuts() {
        let a = NSAlert()
        a.messageText = _L("快捷键一览", "Keyboard Shortcuts")
        a.informativeText = _L("""
新建文件                          ⌘N
保存                              ⌘S
删除选中文件（回收站）              ⌘⌫
AI 问答面板                        ⇧⌘A / ⌥⌘A
命令面板                          ⌃⇧P / ⇧⌘P
视图模式：编辑 / 分屏 / 预览        ⌘1 / ⌘2 / ⌘3
导入文件                          ⌘⇧I
上一篇 / 下一篇文件                ⌥⌘↑ / ⌥⌘↓
切换文件目录                       ⌘⇧O
设置（主题 / 字号 / 缩放）          ⌘,
插入语法（链接/代码/公式/表格）      ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T
附件插入                          ⌥⌘P
""", """
New File                          ⌘N
Save                              ⌘S
Delete Selected File (Trash)      ⌘⌫
AI Chat Panel                     ⇧⌘A / ⌥⌘A
Command Palette                   ⌃⇧P / ⇧⌘P
View Mode: Editor / Split / Preview  ⌘1 / ⌘2 / ⌘3
Import File                       ⌘⇧I
Previous / Next File              ⌥⌘↑ / ⌥⌘↓
Switch Workspace Directory        ⌘⇧O
Settings (Theme / Font / Zoom)    ⌘,
Insert Syntax (Link/Code/Math/Table)  ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T
Insert Attachment                 ⌥⌘P
""")
        a.addButton(withTitle: _L("好", "OK"))
        a.runModal()
    }
}
