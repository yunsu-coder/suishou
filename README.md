# 随手 (MarkNote)

macOS 原生 Markdown 笔记编辑器 —— SwiftUI + AppKit 纯原生路线:**文件即笔记**(`.md`/文本文件直存,id = 相对路径),**文件夹即分类**,资源自动归类。写 → 看 → 存 三件事为核心,其余全部插件化、按需启用。

> 内部代号 MarkNote,产品名「随手」—— 随手一记,即记即成。

## 核心设计

- **文件即笔记**:工作台就是一个普通文件夹,每篇笔记 = 一个 `.md`/文本文件,无私有格式、无锁库。任何编辑器都能打开、可 git 管理、可整体备份迁移
- **文件夹即分类**:子文件夹 = 分类;图片/PDF/视频等资源按类型自动入库到 source/<type>/ 并插入引用
- **轻量化**:核心 = 写(编辑器)→ 看(预览)→ 存(文件直写)。行号/当前行高亮/括号匹配/代码智能/导出/AI 快捷操作/渲染扩展 等全部插件化开关,设置里逐项可关
- **AI 助手(DeepSeek,内置)**:停靠式 AI 面板(⇧⌘A),`@文件名` 引用工作台内文件作上下文;文件代理可读/写/改名/移动/删除;对话历史自动保存;一键「总结对话 → 笔记」

## 界面

- **浏览器式标签页**:顶部标签行与窗口交通灯同高(VS Code 式),点击切换、× 关闭;窗口标题与当前标签一致
- **左侧活动条**:工作台 / 插件市场🧩 / 设置(底部)
- **编辑器**:NSTextView 原生,Markdown 语法着色、当前行高亮、括号匹配、代码智能编辑(全部可关)
- **实时预览**:单 WKWebView 离线渲染 markdown-it + KaTeX + Mermaid + highlight.js,180ms 防抖
- **国际化**:中文 / English / 跟随系统,切换后重启完全生效(VS Code 式)

## 插件系统

声明式插件包(无代码执行,零崩溃风险),市场内置:

| 类别 | 示例 |
| --- | --- |
| 渲染扩展 | `[[⌘S]]` 键帽、`@名字` 提及高亮、引言美化、终端风味代码块 |
| 模板包 | 周报/会议纪要/PRD/复盘、README/API/CHANGELOG、康奈尔/费曼/错题本、邮件、OKR/项目计划 |
| (已清理) | 与内置重复的专家/命令/文件类型/主题包已移除,市场只保留纯增量插件 |

- 位置:`.plugins/<id>/`(工作台)或 `~/Library/Application Support/MarkNote/plugins/<id>/`(全局)
- 开关:插件市场(左侧 🧩)或设置 → 插件;默认禁用,显式启用
- 市场 UI 与包元数据(name/desc/features)双语,模板正文中英双语
- 详见 `docs/05-内置插件库.md`

## 运行

```bash
swift run               # 开发运行
./scripts/build-app.sh  # 打包 随手.app (release,输出 build/)
open build/随手.app
```

> `~/Desktop` 下运行会弹「访问桌面」TCC 授权(工作台位置所致),点允许即可;想彻底避免把 app 放入「应用程序」目录。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 新建文件 |
| `⌘S` | 立即保存 |
| `⌘⌫` | 删除选中文件(回收站,可撤销) |
| `⌘1/2/3` | 仅编辑 / 分屏 / 仅预览 |
| `⌘⇧I` | 导入文件; `⌘⇧O` 切换工作台目录 |
| `⌥⌘↑/↓` | 上一篇 / 下一篇文件 |
| `⌘,` | 设置(语言/外观/字体/毛玻璃) |
| `⇧⌘A` / `⌥⌘A` | AI 面板开关 |
| `⌃⇧P` | 命令面板 |
| `⌃+滚轮` | 分层缩放(编辑器=字号,预览=正文,其余=窗口) |
| `⌘B` | 显示/隐藏资源管理器 |

「帮助」→「快捷键一览…」随时查看。

## 支持语法

- Callout: `::: tip|note|warning|danger|info|details`
- 脚注、任务列表、`==标记==`、`~下标~`、`^上标^`、`++下划线++`
- KaTeX 公式、Mermaid 图表、代码高亮(41 语言)
- 附件卡: `@[文件名](相对路径)` → 预览渲染为卡片,点击打开

## 技术要点

| 组件 | 方案 |
| --- | --- |
| 编辑 | NSTextView(NSViewRepresentable)+ LineNumberRulerView |
| 预览 | 单 WKWebView + 离线管线(markdown-it/KaTeX/Mermaid/hljs) |
| 数据 | 文件直写(.atomic)+ 外部修改监听 + 冲突三选处理 |
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
├── Tests/MarkNoteTests/          # 50+ 测试
├── plugins-market/               # 插件库(9 包)
├── plugins-samples/              # 示例包
├── scripts/build-app.sh          # 打包 .app
└── docs/05-内置插件库.md         # 插件文档
```

## 路线图(插件生态)

- 插件市场:远程安装/更新通道、渲染插件文档化(P3)
- 模板与专家包继续扩充
- 移动端/云同步(iCloud/git)审视
