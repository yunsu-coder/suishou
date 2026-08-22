import SwiftUI
import AppKit

/// 设置面板（⌘,）
struct SettingsView: View {
    @Environment(NotesStore.self) private var store
    @AppStorage("editorFontSize") private var editorFontSize = 13.0
    @AppStorage("previewFontScale") private var previewFontScale = 1.0

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environment(store)
                .tabItem { Label("通用", systemImage: "gear") }
            ThemeSettingsTab()
                .environment(store)
                .tabItem { Label("主题", systemImage: "paintpalette") }
            EditorSettingsTab(editorFontSize: $editorFontSize, previewFontScale: $previewFontScale)
                .tabItem { Label("编辑", systemImage: "textformat.size") }
        }
        .frame(width: 480, height: 380)
    }
}

private struct GeneralSettingsTab: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        Form {
            Section("笔记目录") {
                Text(store.notesDir.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .truncationMode(.middle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                HStack {
                    Button("选择目录…") { store.chooseNotesDirectory() }
                    Button("在 Finder 中显示") {
                        NSWorkspace.shared.open(store.notesDir)
                    }
                    Spacer()
                }
                Text("支持直接指向 start 项目的 notes 目录，两者无缝共用同一份数据。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }
}

/// 主题选择：每套主题一行（色点 + 名称 + 描述）
private struct ThemeSettingsTab: View {
    @Environment(NotesStore.self) private var store

    var body: some View {
        Form {
            Section {
                ForEach(Theme.allCases) { theme in
                    Button {
                        store.setTheme(theme)
                    } label: {
                        HStack(spacing: 10) {
                            swatch(theme)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(theme.name)
                                    .font(.callout.weight(.medium))
                                Text(theme.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: store.themeVersion >= 0 && currentTheme == theme ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(currentTheme == theme ? Color.accentColor : Color.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("外观主题")
            } footer: {
                Text("预览区、编辑器配色与 macOS 深浅外观随主题联动。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }

    /// 主题色板预览点（预览底色 + accent 色）
    private func swatch(_ t: Theme) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(bg(t))
                .frame(width: 34, height: 34)
            RoundedRectangle(cornerRadius: 6).strokeBorder(t.accent.opacity(0.7))
                .frame(width: 34, height: 34)
            Circle().fill(t.accent)
                .frame(width: 9, height: 9)
        }
    }

    private func bg(_ t: Theme) -> Color {
        switch t {
        case .system: return Color(nsColor: .windowBackgroundColor)
        case .night: return Color(red: 0.043, green: 0.043, blue: 0.078)
        case .dawn: return Color(red: 0.973, green: 0.96, blue: 0.94)
        case .forest, .violet: return Color(red: 0.07, green: 0.09, blue: 0.07)
        }
    }
}

private struct EditorSettingsTab: View {
    @Binding var editorFontSize: Double
    @Binding var previewFontScale: Double
    @AppStorage("previewFont") private var previewFont = "system"

    var body: some View {
        Form {
            Section("编辑器") {
                VStack {
                    HStack {
                        Text("源码字号")
                        Spacer()
                        Text("\(editorFontSize, specifier: "%.0f") pt")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $editorFontSize, in: 11...20, step: 1)
                }
            }
            Section("预览") {
                VStack {
                    HStack {
                        Text("正文缩放")
                        Spacer()
                        Text("\(previewFontScale, specifier: "%.0f%%")")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $previewFontScale, in: 0.75...1.5, step: 0.05)
                }
                Picker("预览字体", selection: $previewFont) {
                    Text("系统").tag("system")
                    Text("苹方 PingFang").tag("pingfang")
                    Text("楷体 Kaiti").tag("kaiti")
                    Text("宋体 Songti").tag("songti")
                    Text("等宽 Mono").tag("mono")
                }
            }
            Spacer()
        }
        .padding()
        .formStyle(.grouped)
    }
}
