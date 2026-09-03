# 随手 (MarkNote)

**中文** | [English](README.en.md)

_A macOS Markdown notes editor / local-first note-taking app. Files are the storage; AI assistant (DeepSeek) and a declarative plugin system included. SwiftUI, offline-first, Obsidian alternative._

一个 macOS 上的 Markdown 笔记编辑器。技术栈 SwiftUI + AppKit;核心思路是把笔记保存为普通文件,尽量避免私有格式。

> 内部代号 MarkNote,产品名「随手」。

## 设计

- **文件即笔记**:工作台就是一个文件夹,每篇笔记对应一个 `.md` 或文本文件。想换编辑器、想备份迁移、想放进 git,都直接可用
- **文件夹即分类**:子文件夹当作分类;图片、PDF、视频等资源按类型放到 source/ 下,并在笔记里插入引用
- **功能可裁剪**:写 → 看 → 存 是核心;行号、当前行高亮、括号匹配、代码智能、导出、AI 快捷操作、渲染扩展等开关在设置里逐项控制
- **AI 助手(可选)**:停靠式 AI 面板(⇧⌘A),支持 `@文件名` 引用工作台文件、文件读写代理、对话历史、总结到笔记。使用 DeepSeek 接口,内置可用

## 界面

- 顶部标签行与窗口交通灯同高,点击切换、× 关闭;窗口标题跟随当前标签
- 左侧:工作台 / 插件市场 / 设置(底部)
- 编辑器基于 NSTextView;预览为单个 WKWebView,离线渲染 markdown-it、KaTeX、Mermaid、highlight.js
- 中文 / English / 跟随系统,切换语言后重启生效(与 VS Code 一致)

## 插件

插件是声明式的(manifest + 数据文件,不执行用户代码),在插件市场里启用/禁用,默认关闭。当前内置:

| 类别 | 内容 |
| --- | --- |
| 渲染扩展 | `[[⌘S]]` 键帽、`@名字` 提及高亮、引言美化、终端风味代码块 |
| 模板包 | 周报/会议纪要/PRD/复盘、README/API/CHANGELOG、康奈尔/费曼/错题本、邮件、OKR/项目计划 |

插件目录:工作台 `.plugins/<id>/` 或 `~/Library/Application Support/MarkNote/plugins/<id>/`;包元数据与模板正文含中英文。详见 `docs/05-内置插件库.md`。

## 运行

```bash
swift run               # 开发运行
./scripts/build-app.sh  # 打包 build/随手.app
open build/随手.app
```

> 若工作台在桌面目录,首次运行会弹系统「访问桌面」授权;放「应用程序」目录可避免。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 新建文件 |
| `⌘S` | 立即保存 |
| `⌘⌫` | 删除选中文件(可撤销) |
| `⌘1/2/3` | 仅编辑 / 分屏 / 仅预览 |
| `⌘⇧I` | 导入文件; `⌘⇧O` 切换工作台目录 |
| `⌥⌘↑/↓` | 上一篇 / 下一篇文件 |
| `⌘,` | 设置(语言/外观/字体/毛玻璃) |
| `⇧⌘A` / `⌥⌘A` | AI 面板开关 |
| `⌃⇧P` | 命令面板 |
| `⌃+滚轮` | 分层缩放(编辑器=字号,预览=正文,其余=窗口) |
| `⌘B` | 显示/隐藏资源管理器 |

「帮助」→「快捷键一览…」可随时查看。

## 支持的语法

- Callout:`::: tip|note|warning|danger|info|details`
- 脚注、任务列表、`==标记==`、`~下标~`、`^上标^`、`++下划线++`
- KaTeX 公式、Mermaid 图表、代码高亮
- 附件卡:`@[文件名](相对路径)` → 预览渲染为卡片,点击打开

## 技术要点

| 组件 | 方案 |
| --- | --- |
| 编辑 | NSTextView(NSViewRepresentable)+ LineNumberRulerView |
| 预览 | 单 WKWebView + 离线管线(markdown-it/KaTeX/Mermaid/hljs) |
| 数据 | 文件直写(.atomic)+ 外部修改监听 + 冲突处理 |
| 版本 | 保存前自动快照(10 份) |
| AI | DeepSeek 流式 SSE、工具调用式文件代理、对话历史落盘 |
| 国际化 | `_L(zh, en)` 双语文案,系统菜单随 app 语言 |

## 结构

```
note/
├── Package.swift                 # SPM 可执行目标 (macOS 14+)
├── Sources/MarkNote/
│   ├── MarkNoteApp.swift         # @main + 菜单/语言
│   ├── Models/                   # Note/AIExpert/Plugin/FeatureModules/L10n...
│   ├── Store/                    # NotesStore/PluginManager/Workspace/WorkspaceAgent
│   ├── Editor/                   # NSTextView/行号/高亮
│   ├── Views/                    # 侧栏/编辑器/预览/AI面板/市场/设置
│   └── Resources/                # preview 管线 + vendor(离线)
├── Tests/MarkNoteTests/          # 测试
├── plugins-market/               # 插件库
├── plugins-samples/              # 示例包
├── scripts/build-app.sh          # 打包 .app
└── docs/05-内置插件库.md         # 插件文档
```

## 待办

- 插件市场远程安装/更新通道
- 更多模板与专家包
- 移动端 / 云同步(未开始)
