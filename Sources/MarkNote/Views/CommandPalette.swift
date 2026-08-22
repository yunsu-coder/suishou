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

        items.append(CommandItem(key: "file.new", title: "新建笔记…", category: "文件", icon: "square.and.pencil") { store.createNote() })
        items.append(CommandItem(key: "file.newFolder", title: "新建文件夹…", category: "文件", icon: "folder.badge.plus") {
            NotificationCenter.default.post(name: .requestNewCategory, object: nil)
        })
        items.append(CommandItem(key: "file.importFiles", title: "导入文件…", category: "文件", icon: "square.and.arrow.down") {
            NotificationCenter.default.post(name: .requestImportFiles, object: nil)
        })
        items.append(CommandItem(key: "file.importFolder", title: "导入文件夹…", category: "文件", icon: "folder") {
            NotificationCenter.default.post(name: .requestImportFolder, object: nil)
        })
        items.append(CommandItem(key: "file.delete", title: "删除选中笔记（移入回收站）", category: "文件", icon: "trash") {
            store.deleteSelection()
        })
        items.append(CommandItem(key: "file.attachments", title: "打开附件面板", category: "文件", icon: "paperclip") {
            NotificationCenter.default.post(name: .requestAttachments, object: nil)
        })
        items.append(CommandItem(key: "file.versions", title: "历史版本…", category: "文件", icon: "clock.arrow.circlepath") {
            NotificationCenter.default.post(name: .requestVersions, object: nil)
        })
        items.append(CommandItem(key: "export.md", title: "导出 Markdown…", category: "导出", icon: "square.and.arrow.up") { ExportService.exportMD(store) })
        items.append(CommandItem(key: "export.txt", title: "导出纯文本…", category: "导出", icon: "doc.plaintext") { ExportService.exportTXT(store) })
        items.append(CommandItem(key: "export.pdf", title: "导出 PDF…", category: "导出", icon: "doc.richtext") { ExportService.exportPDF(store) })
        items.append(CommandItem(key: "export.html", title: "导出 HTML…", category: "导出", icon: "globe") { ExportService.exportHTML(store) })

        items.append(CommandItem(key: "view.editor", title: "仅编辑", category: "视图", icon: "text.cursor") {
            Self.setMode(EditorMode.editor.rawValue)
        })
        items.append(CommandItem(key: "view.split", title: "分屏", category: "视图", icon: "rectangle.split.2x1") {
            Self.setMode(EditorMode.split.rawValue)
        })
        items.append(CommandItem(key: "view.preview", title: "仅预览", category: "视图", icon: "doc.richtext") {
            Self.setMode(EditorMode.preview.rawValue)
        })

        for theme in Theme.allCases {
            items.append(CommandItem(key: "theme." + theme.rawValue, title: "主题：\(theme.name)", category: "主题", icon: "paintpalette") {
                store.setTheme(theme)
            })
        }

        for mode in NotesStore.SortMode.allCases {
            items.append(CommandItem(key: "sort." + mode.rawValue, title: "排序：\(mode.name)", category: "排序", icon: "arrow.up.arrow.down") {
                store.sortMode = mode
            })
        }

        items.append(CommandItem(key: "help.shortcuts", title: "查看快捷键一览…", category: "帮助", icon: "keyboard") {
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
            items.append(CommandItem(key: "insert." + kind.rawValue, title: "插入：\(kind.title)", category: "插入", icon: icon) {
                NotificationCenter.default.post(name: .insertMarkdown, object: kind)
            })
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
                TextField("输入命令…", text: $query)
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
                Text("没有匹配命令")
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
        a.messageText = "快捷键一览"
        a.informativeText = """
        新建笔记                          ⌘N
        保存                              ⌘S
        删除选中笔记（回收站）              ⌘⌫
        命令面板                          ⌃⇧P / ⇧⌘P
        视图模式：编辑 / 分屏 / 预览        ⌘1 / ⌘2 / ⌘3
        导入文件                          ⌘⇧I
        上一篇 / 下一篇笔记                ⌥⌘↑ / ⌥⌘↓
        切换笔记目录                       ⌘⇧O
        设置（主题 / 字号 / 缩放）          ⌘,
        插入语法（链接/代码/公式/表格）      ⌥⌘L · ⌥⌘C · ⌥⌘K · ⌥⌘F · ⌥⌘T
        附件插入                          ⌥⌘P
        """
        a.addButton(withTitle: "好")
        a.runModal()
    }
}
