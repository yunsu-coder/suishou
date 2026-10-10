import SwiftUI

/// 素材面板（编辑区上方）—— 高度可拖。
/// 拖动草稿状态收在这个小视图内：逐帧只重渲面板自身，不牵动编辑器 / 预览整棵树（拖动更顺）。
struct AssetTopPanel: View {
    let spec: PluginView
    @Environment(NotesStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("assetTopPanelHeight") private var heightStored: Double = 480
    @State private var heightDraft: Double?
    private var height: Double { heightDraft ?? heightStored }

    var body: some View {
        VStack(spacing: 0) {
            AssetGridView(spec: spec)
                .environment(store)
                .frame(height: height)
            PanelResizeHandle(value: Binding(
                    get: { height },
                    set: { v in
                        withAnimation(AppMotion.liveResize(reduceMotion)) { heightDraft = v }
                    }),
                minValue: 240, maxValue: 900, defaultValue: 480,
                onCommit: {
                    if let d = heightDraft { heightStored = d; heightDraft = nil }
                },
                help: _L("拖动调整素材面板高度，双击复位到 480",
                         "Drag to resize the asset panel, double-click to reset (480)"))
        }
        .background(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground))
    }
}
