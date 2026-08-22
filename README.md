# 随手

macOS 原生 Markdown 笔记编辑器 —— SwiftUI + AppKit「性能为王」路线：纯原生文本系统（NSTextView）+ 单实例 WebView 实时预览，数据格式与 [start](../../Desktop/start) 项目的笔记模块**完全兼容**。

> 内码 MarkNote，对外产品名「随手」—— 随手一记，即记即成。

```
┌──────────────┬──────────────────────────┬──────────────────────────┐
│  侧边栏       │  Markdown 源码编辑器      │  实时预览（WKWebView）      │
│  搜索/分类     │  行号 · 撤销 · 等宽字体    │  markdown-it + KaTeX      │
│  笔记列表      │  （NSTextView 原生）      │  + Mermaid + highlight.js │
└──────────────┴──────────────────────────┴──────────────────────────┘
                状态栏：字数 · 行数 · 已保存 · 版本
```

## 亮点

- **性能**：编辑器走 AppKit 原生文本系统，预览只用一个 WKWebView（180ms 防抖全量渲染），无 Electron 包袱
- **与 start 无缝共存**：数据就是 `notes/<id>.json` + `.versions/` + `.categories.json`（`⌘⇧O` 可直接指向 start 项目的 notes 目录）
- **自动保存**：500ms 防抖落盘，保存前自动快照（最多 10 份），工具栏时钟图标或状态栏「版本」随时回看恢复
- **渲染管线完整移植**：callout（`::: tip`）、脚注、任务列表、KaTeX 公式、Mermaid 图表（懒加载）、41 种语言代码高亮，全部离线内置（约 5MB）
- **导入**：`⌘⇧I` 批量导入 .md/.txt；或直接把文件拖进侧边栏/编辑器（每个文件成为一篇笔记）
- **图片附件**：编辑器内直接粘贴（⌘V 截图/复制图片）或拖入图片 → 自动存入 `images/<noteId>/` 并插入引用；图片管理面板（缩略图/复制引用/Finder 显示/删除）；预览里点击图片看大图
- **5 套主题**：跟随系统 / 夜航者（start 粉暗色系）/ 晨曦（暖白琥珀）/ 墨林（墨绿苔青）/ 紫鸢（深紫鸢尾），app 深浅外观 + 预览配色联动（⌘, 选择）
- **三种视图模式**：工具栏切换 仅编辑 / 分屏 / 仅预览
- **导出**：PDF（离屏渲染）、独立 HTML（内联样式）、Markdown、纯文本（工具栏 + 文件菜单）
- **原生观感**：材质侧边栏、行号标尺当前行高亮

## 运行

```bash
swift run              # 开发运行
./scripts/build-app.sh # 打包 随手.app（release，输出到 build/）
open build/随手.app
```

## 图标

**主体来自网络开源素材**（非手绘）：

- 蛙：微软 [Fluent UI Emoji](https://github.com/microsoft/fluentui-emoji) 3D Frog（MIT 协议），
  `assets/frog_3d.png`（官方 256px）+ 脚本内两级 Lanczos 插值放大，细节无损
- 底：深蓝紫空间渐变 + 顶部照明柔光 + 蛙后暖光盘（合成于 `scripts/make-icon.swift`）

合成脚本可复现：`swift scripts/make-icon.swift build/icon-1024.png`；
打包脚本自动生成 iconset → AppIcon.icns。换蛙：把任意 `assets/frog_3d.png` 换成新素材即可。

> 注意：app 位于 ~/Desktop/ 下时 macOS 每次重签名都会请求"访问桌面"权限；
> 需要避开请把 build/随手.app 移入「应用程序」目录。

## 性能与内存设计

- **打字热路径**：编辑器 `updateNSView` 用三端采样指纹（O(1)）代替每帧全量字符串比较，大文档连续输入不卡顿
- **图片内联缓存**：data URL 按 相对路径+mtime 缓存，打字时每 180ms 渲染不重复读盘/base64（≤5MB 图片）；渲染缓存 mtime 变化自动失效
- **渲染缓存（Web 侧）**：highlight.js LRU（600 块）+ mermaid 按源码缓存（100 张），未变化的代码块/图表不再重复计算
- **附件面板**：ImageIO 缩略图解码（256px），几十张图不全量解码进内存
- **WKWebView**：messageHandler 反注册防泄漏；保存/索引 IO 走串行队列，外部修改 0.5s 防抖刷新

> 首次启动若 macOS 弹出「访问 桌面」权限询问（app 位于桌面文件夹内所致），点**允许**即可；
> 选择目录时若指向 start 的 notes/，注意那是 Web 版正在使用的目录，两程序并发用同一目录时
> 本应用会自动感知外部修改并刷新列表。

## 快捷键

| 快捷键 | 功能 |
| --- | --- |
| `⌘N` | 新建笔记 |
| `⌘S` | 立即保存 |
| `⌘⌫` | 删除选中笔记（进回收站，可撤销） |
| `⌘1` / `⌘2` / `⌘3` | 仅编辑 / 分屏 / 仅预览 |
| `⇧+⬇` / `⇧+⬆` | 逐行扩展 / 撤退多选（列表聚焦时） |
| `⌘⇧I` | 导入 Markdown 文件 |
| `⌥⌘↑` / `⌥⌘↓` | 上一篇 / 下一篇笔记 |
| `⌘⇧O` | 切换笔记目录 |
| `⌘,` | 设置（主题 / 字号 / 预览缩放） |
| `⌘V` | 粘贴图片（自动存附件并插入引用） |

「帮助」菜单 →「快捷键一览…」可随时查看。

## 界面设计（v1.5 资源管理器）

```
┌──┬────────────────┐   活动条：笔记 ▣ / 回收站 🗑（VSCode 式）
│▣ │ ▾ 笔记         [+菜单]  面板标题行：新建笔记/新建文件夹
│🗑│ 🔍 搜索笔记               紧凑搜索行（全文）
│  │ ▾ ● 未分类  5    │   文件夹树：chevron 折叠/色点/计数
│  │    ▪ 笔记1       │   · 文件夹 = 分类（文件夹 menu：重命名/新建笔记/删除）
│  │    ▪ 笔记2       │   · 搜索时树转为平铺结果（关键词高亮）
│  │ ▸ ● 示例  1      │
│  │────────────────│
│  │ 目录路径 · 计数  │   底部信息
└──┴────────────────┘
```

## 交互特性（v1.3）

- 当前笔记固定列表首位（编辑时不乱跳）；自动保存 + 版本快照
- **全文搜索**（正文级 + 关键词高亮，空格分词，`N/M 匹配` 反馈）
- **光标位置记忆**：切回笔记回到上次编辑处
- **预览滚动跟随**：光标移动时预览按最近标题滚动
- **编辑器**：Markdown 语法着色、当前行高亮、列表/引用回车自动延续、Tab = 4 空格
- **回收站**（误删恢复）与**分类分组视图**（组头可折叠）
- **联网图片**（下载缓存）、预览字体设置（苹方/楷体/宋体/等宽）
- 「插入」菜单：链接/代码/代码块/公式/表格/图片（⌥⌘L·C·K·F·T）
- 窗口标题跟随笔记、状态栏显示光标 行:列
- 菜单：视图（模式/主题）/ 插入 / 导出 / 帮助 / 关于

## 图片约定

- 图片保存于 `<notesDir>/images/<noteId>/`，正文里引用相对路径 `images/<noteId>/xxx.png`（与 start 同一数据目录时互不干扰）
- 预览渲染时图片以 data URL 内联（单张 ≤ 5MB），离线、无 file 权限问题
- 粘贴的 TIFF/BMP 位图统一转 PNG；Finder 拖入的 JPG/GIF 等保持原格式

## 语法（与 start 一致）

- Callout：`::: note|tip|warning|danger|info|details` … `:::`
- 脚注：`[^1]` / `[^1]: 内容`
- 任务列表：`- [ ]` / `- [x]`
- 表格（GFM）、`==标记==`、`~下标~`、`^上标^`、`++下划线++`
- 公式：行内 `$E=mc^2$`，块级 `$$\int_0^1 x\,dx$$`
- 图表：```` ```mermaid ```` 代码块（首次出现时懒加载渲染器）
- 代码块：任意语言高亮；未知语言自动检测

## 技术要点

| 组件 | 方案 |
| --- | --- |
| 编辑 | `NSTextView`（NSViewRepresentable）+ `LineNumberRulerView`（NSRulerView 原生行号）|
| 预览 | 单 `WKWebView` + `preview.html/css/js`（Resources/），`evaluateJavaScript` 防抖全量渲染 |
| 数据 | JSON 文件直写（`.atomic`），磁盘 IO 串行队列 `marknote.io`，FS 事件监听外部修改 |
| 版本 | 保存前 `copyItem` 快照，保留最近 10 份（与 start 同规则） |
| 渲染 | markdown-it + 插件 + KaTeX + highlight.js + mermaid，全部 UMD 本地 vendor（`scripts/fetch-vendor.sh` 可复现抓取） |

## 结构

```
note/
├── Package.swift                # SPM 可执行目标（macOS 14+）
├── Sources/MarkNote/
│   ├── MarkNoteApp.swift        # @main 入口 + 菜单/快捷键命令
│   ├── Models/Note.swift        # start 兼容模型（宽容解码）
│   ├── Store/NotesStore.swift   # 数据层（@Observable，自动保存/快照/分类/FS 监听）
│   ├── Editor/                  # NSTextView 封装 + 行号标尺
│   ├── Views/                   # 侧边栏/分屏/预览/版本/设置
│   └── Export/ExportService.swift # PDF(离屏 WKWebView)/MD/TXT
├── Resources/                   # preview 管线 + vendor JS（离线）
├── scripts/build-app.sh         # 打包 .app（含 Info.plist + 资源合并 + ad-hoc 签名）
└── scripts/fetch-vendor.sh      # 重新抓取 vendor 前端依赖
```

## 路线图（v2 候选）

- 拖拽/粘贴图片 → 附件接入预览
- 双链笔记 `[[wiki]]` + 反链
- 全文搜索索引（现在的搜索与 start 一致：标题 + 120 字摘要）
- 文件夹式组织、导出 DOCX
- 编辑器：当前行高亮、代码折叠、Vim 模式
