import SwiftUI

/// 主界面 —— NavigationSplitView：侧边栏（列表/搜索/分类）+ 分屏编辑器
struct ContentView: View {
    @Environment(NotesStore.self) private var store
    @State private var showVersions = false
    @State private var showExportMenu = false
    @State private var showPalette = false
    @AppStorage("editorMode") private var mode = EditorMode.split.rawValue

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(showVersions: $showVersions)
        } detail: {
            EditorView(showVersions: $showVersions)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbarItems }
        .tint(currentTheme.accent)
        .preferredColorScheme(currentTheme.colorScheme)
        .id(store.themeVersion) // 主题切换时整体重建（应用深浅/色调生效）
        // 菜单「视图」切模式 → 同步工具栏 AppStorage 状态
        .onReceive(NotificationCenter.default.publisher(for: .editorModeDidChange)) { _ in
            let raw = UserDefaults.standard.string(forKey: "editorMode") ?? EditorMode.split.rawValue
            mode = raw
        }
        // 多选集：恰好选中 1 篇时打开（单击=选中+打开；⇧/⌘ 多选只选不开）
        // 防线：剔除非笔记行（文件夹行会被 macOS List 以隐性 identity 误选 —— 折叠/扩容时
        // 该选择集会导致 openNote(文件夹id) → "读取失败"）
        .onChange(of: store.selectedNoteIDs) { _, newSet in
            let valid = newSet.filter { id in store.index.contains(where: { $0.id == id }) }
            if valid.count != newSet.count {
                store.selectedNoteIDs = valid
                return
            }
            if valid.count == 1, let only = valid.first {
                store.openNote(only)
            }
        }
        // 轻提示 Toast：点击屏幕任意处关闭，或 3.5 秒自动消失
        .overlay {
            if store.hintMessage != nil {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { store.hideHint() }
            }
        }
        .overlay(alignment: .top) {
            if let hint = store.hintMessage {
                HintToast(text: hint)
                    .id(store.hintToken)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: store.hintMessage)
        // 命令面板（Ctrl+Shift+P）：顶部居中浮层；点击任意处关闭
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
            showPalette = true
        }
        .overlay {
            if showPalette {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture { showPalette = false }
            }
        }
        .overlay(alignment: .top) {
            if showPalette {
                CommandPalette(isPresented: $showPalette)
                    .environment(store)
            }
        }
        .animation(.snappy(duration: 0.2), value: showPalette)
    }

    /// 轻提示横幅（任意点击 / 自动消失；不阻塞、不要求点"好"）
    private struct HintToast: View {
        let text: String
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.callout)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
            .shadow(color: .black.opacity(0.22), radius: 14, y: 4)
            .contentShape(Rectangle())
        }
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        // 侧边栏切换是系统自带项，其余放在尾部。
        // 注：模式切换不在工具栏 —— 走 ⌘1/2/3 与「视图」菜单（带 ✓）。
        //     新建/导入同理，已收进侧栏「+」与拖拽。
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                showVersions = true
            } label: {
                Label("历史版本", systemImage: "clock.arrow.circlepath")
            }
            .disabled(store.selectedNoteID == nil)
            .help("查看历史版本")

            Menu {
                Button("导出 Markdown…") { ExportService.exportMD(store) }
                Button("导出纯文本…") { ExportService.exportTXT(store) }
                Divider()
                Button("导出 PDF…") { ExportService.exportPDF(store) }
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .disabled(store.selectedNoteID == nil)
            .help("导出笔记")
            // 注：删除不进工具栏 —— ⌘⌫ / 行右键 / 文件菜单均可删（可撤销）
        }
    }
}

/// 笔记未选择 / 数据目录为空的占位视图
struct EmptyStateView: View {
    @Environment(NotesStore.self) private var store
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            Text("无选中笔记")
                .font(.title3.weight(.semibold))
            Text("左侧选择一篇笔记，或新建一篇（⌘N）")
                .font(.callout)
                .foregroundStyle(.secondary)
            if store.selectedNoteID == nil && store.filteredIndex.isEmpty {
                Button("新建第一篇笔记") { store.createNote() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
