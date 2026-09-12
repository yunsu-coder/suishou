import SwiftUI
import AppKit
import WebKit

/// 主界面 —— NavigationSplitView：侧边栏（列表/搜索/分类）+ 分屏编辑器
struct ContentView: View {
    @Environment(NotesStore.self) private var store
    @State private var showVersions = false
    @State private var showExportMenu = false
    @State private var showPalette = false
    @State private var showQuickOpen = false
    @AppStorage("editorMode") private var mode = EditorMode.split.rawValue
    @AppStorage("aiPanelVisible") private var aiPanelVisible = false
    /// AI 问答会话（停靠面板持有同一实例：折叠/隐藏不丢历史）
    @State private var aiModel = AIChatModel()
    /// 侧栏显示态（⌘B 切换；自绘布局，不复用系统分栏）
    @State private var sidebarHidden = false
    /// 阅读专注态（临时 UI 状态：隐藏侧栏 / AI 面板 / tab 栏，只留预览；退出即还原，不写偏好）
    @State private var readerFocus = false
    @State private var readerKeyMonitor: Any?
    /// 鼠标是否停在窗口顶部 8pt 内（含标题栏区域，由 mouseMoved 监听驱动；
    /// 低频变化，可安全放在父级 —— 高频的条悬停状态留在 ReaderFocusOverlay 内部）
    @State private var readerTopZone = false
    @State private var readerMouseMonitor: Any?
    /// 资源管理器宽度（拖拽手柄调整；持久化）
    @AppStorage("explorerWidth") private var explorerWidth = 170.0
    /// ⌃+滚动 分层缩放监视器（与设置页同键；本窗口级别的作用目标也在此裁决）
    @State private var ctrlScrollMonitor: Any?
    /// ⇧⌘/ 反缩进监视器：该键被系统「帮助搜索」以菜单级 keyEquivalent 占用（非菜单项，剥不掉）
    /// —— 只能在本层先于菜单处理截获；编辑器持焦时消费，否则放行给帮助
    @State private var helpSlashMonitor: Any?
    /// AI 面板 ⌥⌘A 本地监视器（菜单快捷键在文本域聚焦时可能被吞；监视器保证全局生效）
    @State private var aiShortcutMonitor: Any?
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("previewFontScale") private var previewFontScale = 1.0
    /// 启用中的插件主题 token（变化 → .id 整体重建；深浅/色调全局生效）
    @State private var pluginThemeToken = "-"
    /// 主题彩蛋覆盖层
    @State private var easterEggActive = false
    /// 主区域视图（视图插件启用后可选「卡片墙」）
    @AppStorage("mainViewKind") private var mainViewKind = "editor"
    @State private var cardsView: PluginView?
    @State private var easterEggSymbols: [String] = []
    @State private var easterEggMessage: String?
    @State private var easterEggDismiss: DispatchWorkItem?

    /// AI 面板开关（⌥⌘A / ⇧⌘A 双组合，keyCode 0）；独立监视器，菜单快捷键失效时兜底
    private func installAIShortcutMonitor() {
        aiShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            guard event.keyCode == 0 else { return event }   // kVK_ANSI_A
            let mods = event.modifierFlags.intersection([.command, .option, .shift])
            guard mods == [.command, .option] || mods == [.command, .shift] else { return event }
            NotificationCenter.default.post(name: .aiPanelToggle, object: nil)
            return nil
        }
    }

    /// ⇧⌘/ 反缩进监视器（独立函数化，同 ⌃滚轮监视器）
    private func installHelpSlashMonitor() {
        helpSlashMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event -> NSEvent? in
            guard event.modifierFlags.contains(.command),
                  event.modifierFlags.contains(.shift),
                  event.keyCode == 44,   // kVK_ANSI_Slash
                  let win = event.window,
                  win.frame.width > 700,
                  win.identifier?.rawValue != "com_apple_SwiftUI_Settings",
                  !win.styleMask.contains(.docModalWindow) else { return event }
            if let tv = win.firstResponder as? MarkdownTextView {
                tv.blockIndent(indent: false)
                return nil
            }
            return event
        }
    }

    /// ⌃+滚轮 分层缩放监视器（独立函数化：此前内联在 .onAppear 导致类型检查超时）
    private func installCtrlScrollMonitor() {
        ctrlScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event -> NSEvent? in
            guard event.modifierFlags.contains(.control) else { return event }
            guard let win = event.window,
                  // 只服务主窗口（设置窗独立场景不在此列）
                  win.frame.width > 700,
                  win.identifier?.rawValue != "com_apple_SwiftUI_Settings",
                  !win.styleMask.contains(.docModalWindow) else { return event }
            // 鼠标一格 ≈ ±1；触控板精确增量 → 0.25 增量平滑缩放
            let step: Double = (event.deltaY < 0 ? 1.0 : -1.0) * (event.hasPreciseScrollingDeltas ? 0.1 : 0.5)
            // 1) 编辑焦点裁决：正在编辑时，无论指针在哪，都只作用于编辑面板
            if win.firstResponder is NSTextView {
                Self.bumpFont(key: "editorFontSize", step: step, minV: 9, maxV: 30)
                return nil
            }
            // 2) 指针兜底：命中预览 / 编辑器面板，各管各的
            if let cv = win.contentView {
                let pt: NSPoint = cv.convert(event.locationInWindow, from: nil)
                if let hit = cv.hitTest(pt) {
                    if Self.inAncestors(hit, is: WKWebView.self) {
                        Self.bumpFont(key: "previewFontScale", step: step, minV: 0.6, maxV: 2.0)
                        return nil
                    }
                    if Self.inAncestors(hit, is: NSTextView.self) {
                        Self.bumpFont(key: "editorFontSize", step: step, minV: 9, maxV: 30)
                        return nil
                    }
                }
            }
            // 3) 失去编辑焦点 → 只缩放窗口
            Self.windowZoom(win, step: step)
            return nil
        }
    }

    /// 滚轮缩放：直接写 UserDefaults（@AppStorage 跨窗口自动同步），并把夹取逻辑集中到此处
    private static func bumpFont(key: String, step: Double, minV: Double, maxV: Double) {
        let cur = UserDefaults.standard.double(forKey: key)
        var next = cur + step
        next = min(maxV, max(minV, next))
        UserDefaults.standard.set(next, forKey: key)
    }

    var body: some View {
        // 阅读专注态 overlay 单独挂一层（body 保持极简：整链过长会让 Swift 类型检查超时）
        mainContentInner
            .overlay(alignment: .top) { readerOverlay }
    }

    private var readerOverlay: some View {
        ReaderFocusOverlay(active: readerFocus,
                           topZone: readerTopZone,
                           accent: appAppearance.accent,
                           onExit: { exitReaderFocus() })
    }

    /// 三段拆分之「布局 + 背景特效」（原单条修饰符链过长，编译器泛型推断会超时）
    @ViewBuilder
    private var mainContentLayout: some View {
        @Bindable var store = store
        // 自绘三栏（macOS 26 NavigationSplitView 侧栏会悬浮覆盖内容 —— (b) 叠盖 bug 的病根，
        // 放弃系统分栏，改为可控 HStack；⌘B 切换侧栏见菜单项）
        HStack(spacing: 0) {
            if !sidebarHidden && !readerFocus {
                SidebarView(showVersions: $showVersions)
                    .frame(width: explorerWidth)
                // 分隔线即拖拽手柄（3pt；拖动调整侧栏宽度，最小 110 / 最大 420）
                ResizeHandle(width: $explorerWidth, minW: 110, maxW: 420)
                    .frame(width: 3)
            }
            // 侧栏显隐按钮已并入编辑器标题栏最左侧（.toggleSidebarRequested 通知）
            // 编辑器 + AI 停靠面板（VSCode Copilot 范式：右侧副栏，可拖分栏调整宽度）
            HSplitView {
                if mainViewKind == "cards", let cards = cardsView {
                    NoteCardsView(spec: cards) { id in
                        mainViewKind = "editor"
                        store.selectedNoteID = id
                        store.openNote(id)
                    }
                    .environment(store)
                    .frame(minWidth: 560)
                } else {
                    EditorView(showVersions: $showVersions, readerFocus: readerFocus)
                        .frame(minWidth: 560)
                }
                if aiPanelVisible && !readerFocus {
                    AIPanelView()
                        .environment(store)
                        .environment(aiModel)
                        .frame(minWidth: 300, idealWidth: 380, maxWidth: 480)
                }
            }
        }
        // 主题氛围特效（按 motion 配置组合；减少动态效果时自动关闭）
        .background { ThemeAmbientLayer() }
        // 插件主题窗口底色（内置主题为 nil，保持系统外观）
        .background {
            if let bg = appAppearance.windowBackground {
                // 非透明主题必须覆盖标题栏安全区；玻璃主题保留可透出的比例。
                Color(nsColor: bg)
                    .opacity(appAppearance.glass > 0 ? max(0.35, 1 - appAppearance.glass) : 1)
                    .ignoresSafeArea()
            } else if appAppearance.glass == 0 {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            }
        }
        // 毛玻璃：窗口透明化 + behindWindow 模糊垫层（桌面壁纸透出；0 时透明背景撤掉还原原生观感）
        .background {
            if appAppearance.glass > 0 {
                Glass.Backdrop(alpha: appAppearance.glass).ignoresSafeArea()
            }
        }
        .background(Glass.Window(enabled: appAppearance.glass > 0, backgroundColor: appAppearance.windowBackground))
        .navigationSplitViewStyle(.balanced)
    }

    /// 三段拆分之「外观 / 身份 / 导入入口」
    private var mainContentChrome: some View {
        mainContentLayout
        // Finder/launch services 打开 .md/.txt → 导入为新文件并打开
        .onOpenURL { url in
            guard url.isFileURL else { return }
            if let id = store.importNote(from: url) {
                store.openNote(id)
            } else {
                store.showHint(_L("无法读取：\(url.lastPathComponent)", "Cannot read: \(url.lastPathComponent)"))
            }
        }
        .tint(appAppearance.accent)
        .font(appAppearance.uiFontFamily.map { Font.custom($0, size: CGFloat(appAppearance.uiFontSize)) } ?? .body)
        .preferredColorScheme(appAppearance.scheme)
        .id("\(store.themeVersion)-\(pluginThemeToken)") // 内置/插件主题切换时整体重建（深浅/色调生效）
        // 插件主题启用/切换 → 重建 token（.id 触发整体重建，插件主题作用于全局）
        .onReceive(NotificationCenter.default.publisher(for: PluginManager.changedNotification)) { _ in
            syncPluginState()
        }
        .onAppear { cardsView = PluginManager.shared.mainAreaView(type: .noteCards) }
    }

    /// 三段拆分之「事件监听 / 浮层 / 生命周期」
    private var mainContentInner: some View {
        mainContentChrome
        .onReceive(NotificationCenter.default.publisher(for: .themeEasterEggTriggered)) { _ in
            triggerThemeEasterEgg()
        }
        // ⌘B 切换侧栏（自绘布局专用）
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebarRequested)) { _ in
            sidebarHidden.toggle()
        }
        // ⌘⇧R / 双击预览空白 → 阅读专注态（临时状态，不改任何偏好）
        .onReceive(NotificationCenter.default.publisher(for: .readerFocusToggle)) { _ in
            toggleReaderFocus()
        }
        // 菜单「视图」切模式 → 同步工具栏 AppStorage 状态
        .onReceive(NotificationCenter.default.publisher(for: .editorModeDidChange)) { _ in
            let raw = UserDefaults.standard.string(forKey: "editorMode") ?? EditorMode.split.rawValue
            mode = raw
        }
        // 多选集（资源管理器语义）：单击=仅选中（焦点留在列表 → ⇧/⌘ 多选可用）；双击=打开
        // 防线（校准）：仅剔除非法 id（文件夹行/已删除的文件），保留其余合法多选
        .onChange(of: store.selectedNoteIDs) { _, newSet in
            let valid = newSet.filter { id in store.index.contains(where: { $0.id == id }) }
            if valid.count != newSet.count {
                store.selectedNoteIDs = valid
            }
        }
        .overlay {
            if easterEggActive {
                ThemeEasterEggOverlay(symbols: easterEggSymbols, message: easterEggMessage)
                    .transition(.opacity)
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
                    .transition(.scale(scale: 0.94)
                        .combined(with: .opacity)
                        .combined(with: .move(edge: .top)))
            }
        }
        // S 级动画 ⑤: Toast 入场升级为单弹簧（response 0.32 / damping 0.82，Apple HIG 手感）
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: store.hintMessage)
        // 命令面板（Ctrl+Shift+P）：顶部居中浮层；点击任意处关闭
        .onReceive(NotificationCenter.default.publisher(for: .commandPaletteRequested)) { _ in
            showPalette = true
        }
        // AI 面板开关（⌥⌘A / 菜单 / 命令面板统一入口）
        .onReceive(NotificationCenter.default.publisher(for: .aiPanelToggle)) { _ in
            aiPanelVisible.toggle()
        }
        .onAppear {
            configureAIModel()
        }
        // 快速打开（⌘P，VSCode Quick Open）
        .onReceive(NotificationCenter.default.publisher(for: .quickOpenRequested)) { _ in
            showQuickOpen = true
            showPalette = false
        }
        .overlay {
            if showPalette || showQuickOpen {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        showPalette = false
                        showQuickOpen = false
                    }
            }
        }
        .overlay(alignment: .top) {
            if showPalette {
                CommandPalette(isPresented: $showPalette)
                    .environment(store)
            }
        }
        .overlay(alignment: .top) {
            if showQuickOpen {
                QuickOpenView(isPresented: $showQuickOpen)
                    .environment(store)
            }
        }
        .animation(.snappy(duration: 0.2), value: showPalette)
        .animation(.snappy(duration: 0.2), value: showQuickOpen)
        // ⌃+滚动 分层缩放（Finder/VSCode 式；方向：向上滚 = 放大，与 Finder 一致）：
        //   焦点在编辑面板（firstResponder = 编辑器）→ 只调编辑器源码字号（含指针在窗口任意处）
        //   指针在预览 → 正文缩放；指针在编辑器（非焦点态）→ 源码字号
        //   其余（焦点在侧栏/搜索/无焦点）→ 只缩放窗口尺寸
        .onAppear {
            installMonitors()
        }
        .onDisappear {
            removeMonitors()
        }
    }

    /// 事件监视器统一安装 / 卸载（分函数化：内联在 body 会让类型检查超时）
    private func installMonitors() {
        installCtrlScrollMonitor()
        installHelpSlashMonitor()
        installAIShortcutMonitor()
        installReaderKeyMonitor()
        installReaderMouseMonitor()
    }

    /// 阅读专注态：鼠标移到窗口顶部（含标题栏 8pt）→ 滑出退出条。
    /// 只在「进入 / 离开」热区时更新状态，移动过程不产生额外重算。
    private func installReaderMouseMonitor() {
        readerMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
            guard readerFocus, let win = event.window,
                  win.identifier?.rawValue != "com_apple_SwiftUI_Settings" else { return event }
            let topInset = max(0, win.frame.height - win.contentLayoutRect.height)
            let fromTop = win.frame.height - event.locationInWindow.y
            let inZone = fromTop <= topInset + 8
            if readerTopZone != inZone { readerTopZone = inZone }
            return event
        }
    }

    /// 插件启用 / 切换后的状态同步（独立函数化：内联在 onReceive 闭包里类型检查超时）
    private func syncPluginState() {
        pluginThemeToken = PluginManager.shared.enabledTheme()?.id ?? "-"
        let hadCards = cardsView != nil
        cardsView = PluginManager.shared.mainAreaView(type: .noteCards)
        // 只有「原本有卡片墙、现在没了」才回编辑器；启动瞬间插件尚未扫完时不动用户选择
        if cardsView == nil, hadCards { mainViewKind = "editor" }
    }

    /// AI 面板数据源接线（独立函数化：内联在 onAppear 闭包里类型检查超时）
    private func configureAIModel() {
        // 面板上下文 = 当前文件内容（停靠面板与编辑器同窗，读 store 实时值）
        aiModel.fileContext = { store.workingText }
        // 文件代理：工作台内读/写/管理（越界、隐藏目录被硬拦截）
        aiModel.agent = WorkspaceAgent(store: store)
        // @ 文件引用数据源
        aiModel.indexProvider = { store.index }
        // 对话历史持久化位置（工作台 .ai-history/，点目录不进入索引）
        aiModel.historyBaseDir = { store.notesDir }
    }

    private func removeMonitors() {
        if let m = ctrlScrollMonitor { NSEvent.removeMonitor(m); ctrlScrollMonitor = nil }
        if let m = helpSlashMonitor { NSEvent.removeMonitor(m); helpSlashMonitor = nil }
        if let m = aiShortcutMonitor { NSEvent.removeMonitor(m); aiShortcutMonitor = nil }
        if let m = readerKeyMonitor { NSEvent.removeMonitor(m); readerKeyMonitor = nil }
        if let m = readerMouseMonitor { NSEvent.removeMonitor(m); readerMouseMonitor = nil }
    }

    // MARK: - 阅读专注态

    private func toggleReaderFocus() {
        if readerFocus { exitReaderFocus() }
        else {
            withAnimation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.22)) { readerFocus = true }
        }
    }

    private func exitReaderFocus() {
        withAnimation(.timingCurve(0.25, 1, 0.4, 1, duration: 0.22)) { readerFocus = false }
    }

    /// Esc 退出；开始打字（无修饰的字符键）也退出，回到编辑。
    private func installReaderKeyMonitor() {
        readerKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard readerFocus else { return event }
            if event.keyCode == 53 {   // Esc
                exitReaderFocus()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            if mods.isEmpty, let ch = event.charactersIgnoringModifiers?.first,
               ch.isLetter || ch.isNumber || ch.isPunctuation || ch == " " {
                exitReaderFocus()
            }
            return event
        }
    }

    private func triggerThemeEasterEgg() {
        let egg = appAppearance.easterEgg
        easterEggSymbols = egg?.symbols ?? ["✨", "🫧", "🍬"]
        easterEggMessage = egg?.message
        easterEggDismiss?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { easterEggActive = true }
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.35)) { easterEggActive = false }
        }
        easterEggDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.4, execute: work)
    }

    /// 自下而上匹配祖先视图（命中面板判断）
    private static func inAncestors(_ v: NSView?, is type: NSView.Type) -> Bool {
        var a = v
        while let cur = a {
            if cur.isKind(of: type) { return true }
            a = cur.superview
        }
        return false
    }

    /// 窗口缩放：中心锚定等比缩放（步进 ±4%，钳位到屏幕可见区与最小 760×520）
    private static func windowZoom(_ win: NSWindow, step: Double) {
        guard let screen = win.screen ?? NSScreen.main else { return }
        let vis = screen.visibleFrame
        let r = win.frame
        let factor = pow(1.04, step)
        let nw = max(760, min(vis.width, r.width * factor))
        let nh = max(520, min(vis.height, r.height * factor))
        win.setFrame(
            NSRect(x: r.midX - nw / 2, y: r.midY - nh / 2, width: nw, height: nh),
            display: true
        )
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
}

/// 文件未选择 / 数据目录为空的占位视图
struct EmptyStateView: View {
    @Environment(NotesStore.self) private var store
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "note.text")
                .font(.system(size: 52))
                .foregroundStyle(.quaternary)
            Text(_LL("无选中文件", "No Note Selected"))
                .font(.title3.weight(.semibold))
            Text(_LL("左侧选择一篇文件，或新建一篇（⌘N）", "Select a note on the left, or create a new one (⌘N)"))
                .font(.callout)
                .foregroundStyle(.secondary)
            if store.selectedNoteID == nil && store.filteredIndex.isEmpty {
                Button(_LL("新建第一篇文件", "Create First Note")) { store.createNote() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}


/// 宽度拖拽手柄：位于分隔线右侧，光标 resizeLeftRight；拖动即改绑定宽度（持久化由调用方负责）
struct ResizeHandle: View {
    @Binding var width: Double
    var minW: Double = 100
    var maxW: Double = 480
    @State private var baseW: Double?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering ? appAppearance.accent.opacity(0.55) : Color(nsColor: .separatorColor))
            .frame(width: 3)
            .padding(.horizontal, 4)   // 视觉 3pt、命中区 ~11pt（好抓）
            .contentShape(Rectangle())
            .onHover { h in
                hovering = h
                h ? NSCursor.resizeLeftRight.push() : NSCursor.pop()
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { v in
                        if baseW == nil { baseW = width }
                        // 手柄在侧栏右侧：拖左（负增量）→ 变窄；拖右 → 变宽
                        let proposed = (baseW ?? width) + Double(v.translation.width)
                        width = min(max(minW, proposed), maxW)
                    }
                    .onEnded { _ in baseW = nil }
            )
            .help(_LL("拖动调整资源管理器宽度", "Drag to resize the explorer width"))
    }
}

/// 阅读专注态的顶部退出条（独立小视图：内联在 ContentView 会让类型检查超时）。
/// 顶部 8pt 热区滑出；鼠标离开热区与条本身 → 自动收起。
private struct ReaderFocusOverlay: View {
    let active: Bool
    let topZone: Bool
    let accent: Color
    let onExit: () -> Void

    /// 条本身的悬停状态放在组件内部：父级持有时高频 hover 会重算整棵视图树（含预览 WebView）。
    @State private var barHovered = false

    private var barVisible: Bool { topZone || barHovered }

    var body: some View {
        if active {
            VStack(spacing: 0) {
                if barVisible {
                    ReaderFocusBar(accent: accent, onExit: onExit, onHoverChange: { barHovered = $0 })
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Spacer()
            }
            .animation(.easeOut(duration: 0.16), value: barVisible)
        }
    }
}

private struct ReaderFocusBar: View {
    let accent: Color
    let onExit: () -> Void
    let onHoverChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "book.pages.fill")
                .font(.system(size: 12))
                .foregroundStyle(accent)
            Text(_L("阅读模式", "Reading mode"))
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(_L("Esc 或开始打字退出", "Esc or start typing to exit"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Button(action: onExit) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(accent.opacity(0.22), lineWidth: 1))
        .onHover(perform: onHoverChange)
    }
}
