# MarkNote (随手)

[中文](README.md) | **English**

_A macOS Markdown notes editor / local-first note-taking app. Files are the storage; a reviewed theme system, a workspace-scoped asset library, and an optional AI assistant (bring your own API key). SwiftUI, offline-first._

A Markdown notes editor for macOS, built with SwiftUI + AppKit. The core idea: keep notes as plain files and avoid proprietary formats as much as possible.

> Internal codename: MarkNote. Product name in Chinese: 随手 ("as you go").

## Design

- **Notes are files**: a workspace is just a folder; each note is a `.md` or text file. Switch editors, back up, migrate, or put it in git — it all just works
- **Workspaces are environments**: every workspace is fully isolated (assets, card wall and indexes only cover the current workspace); the only cross-workspace flow is explicit checkbox import — no auto-sync
- **Asset library**: images / videos / audio / documents are organized under `source/` by type; dropping or pasting files auto-imports them (named `date-description`); reference counts, unused filter, move-to-Trash deletion and cross-workspace import included
- **Trim to what you need**: write → view → save is the core. Line numbers, current-line highlight, bracket match, smart code editing, export — each has its own switch in Settings
- **AI assistant (optional)**: docked AI panel with `@filename` file references, file read/write agent, conversation history, and summarize-to-note. **Bring your own API key** (Settings → Model Service); nothing is bundled

## Interface

- Tab bar sits at the same height as the window traffic lights; click to switch, × to close; the window title follows the active tab
- Left side: Workspace / Plugin Market / Settings (bottom)
- Editor is built on NSTextView; preview is a single WKWebView rendering markdown-it, KaTeX, Mermaid and highlight.js offline
- 33 kinds of editor syntax highlighting (headings/lists/tables/math/media refs/multi-level numbering `1.1.1`…); **preview and editor share the same theme syntax palette**
- Reading focus mode (`⌘⇧R`): hides sidebar / tab bar / status bar for full-width immersion; `Esc` or start typing to exit, or move the mouse to the top edge for the exit bar
- Chinese / English / Follow System; switching language takes effect after restart (same as VS Code)

## Themes

Theme packs (global UI + preview palette) pass a hard quality gate: dedicated fonts, semantic icons, easter eggs, motion, contrast and size must all qualify before entering the market. Four available:

| Theme | Style |
| --- | --- |
| Misty Teal | Paper-light with celadon accent, botanical icons and blossom easter egg |
| Sumi Paper | Xuan paper texture with cinnabar accents |
| Bubble Pop | Pixel candy style with dedicated pixel fonts and icons |
| Forest Night | Dark, deep-green forest |

## Plugins

Plugins are declarative (manifest + data files, no arbitrary user code executed); enabled/disabled in the Plugin Market. The market now keeps only two categories:

| Category | Contents |
| --- | --- |
| Theme packs | See the Themes section above (four, human-reviewed) |
| View plugins | **Card Wall**: notes as day-grouped cards with all/starred/todo filters and todo-progress badges; **Asset Grid**: thumbnail grid, search, unused filter, drag-to-insert, cross-workspace import |

Render enhancements (callouts, tabs, timeline, keycaps, badges, image cards, code copy, …) are built in now and no longer need plugins. Plugin locations: workspace `.plugins/<id>/` or `~/Library/Application Support/MarkNote/plugins/<id>/`. See `docs/05-内置插件库.md` for details.

## Asset library

- Drop files onto the window or paste with `⌘V` → they are copied into `source/<type>/` and named `date-description`; text/note files still go through "import as note"
- Drag from the asset panel into the editor: images inline, video/audio as embedded players (with first-frame thumbnail and duration), other files as attachment cards; it inserts exactly where you drop
- Search, unused-filter and reference counts in the panel; deletion moves to Trash with a "referenced by N notes" warning
- Cross-workspace import is checkbox-based copy; the source workspace stays read-only

## Run

```bash
swift run               # develop
./scripts/build-app.sh  # package build/随手.app
open build/随手.app
```

> If your workspace lives on the Desktop, macOS asks for Desktop access permission on first launch; moving the app to /Applications avoids this.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | New note |
| `⌘S` | Save now |
| `⌘⌫` | Delete selected note (undoable) |
| `⌘1/2/3` | Editor only / Split / Preview only |
| `⌘⇧I` | Import files; `⌘⇧O` switch workspace |
| `⌥⌘↑/↓` | Previous / next note |
| `⌘,` | Settings (language / theme / font size / zoom) |
| `⇧⌘A` / `⌥⌘A` | Toggle AI panel |
| `⌘P` | Quick open (title search) |
| `⌃⇧P` | Command palette |
| `⌘F` / `⇧⌘F` | Find / Replace |
| `⌘⇧R` | Reading focus mode (full-width; press again or Esc to exit) |
| `⌘W` | Close current tab |
| `⌃+scroll` | Layered zoom (editor=font, preview=text, otherwise=window) |
| `⌘B` | Show / hide explorer |

Help → Keyboard Shortcuts… for the full list.

## Markdown support

- Callout: `::: tip|note|warning|danger|info|details`
- Footnotes, task lists, `==mark==`, `~sub~`, `^sup^`, `++underline++`
- KaTeX math, Mermaid diagrams, code highlighting
- Tables (GFM), multi-level numbering `1.` / `1.1` / `1.1.1` (preview indents by level)
- Images: paste/drag into the asset library; short refs like `![caption](img/file.png)` in notes
- Video / audio: dragging from the asset panel generates `<video>` / `<audio>` embedded players
- Attachment cards: `@[filename](relative/path)` renders as a card in preview, click to open

## Tech notes

| Component | Approach |
| --- | --- |
| Editing | NSTextView (NSViewRepresentable) + LineNumberRulerView |
| Preview | Single WKWebView + offline pipeline (markdown-it/KaTeX/Mermaid/hljs) |
| Data | Direct file writes (.atomic) + external-change watcher + conflict handling |
| Versions | Auto snapshot before each save (10 kept) |
| AI | DeepSeek streaming SSE, tool-calling file agent, chat history on disk |
| i18n | `_L(zh, en)` dual strings; system menus follow app language |

## Structure

```
note/
├── Package.swift                 # SPM executable target (macOS 14+)
├── Sources/MarkNote/
│   ├── MarkNoteApp.swift         # @main + menus/language
│   ├── Models/                   # Note/AIExpert/Plugin/FeatureModules/L10n...
│   ├── Store/                    # NotesStore/PluginManager/Workspace/WorkspaceAgent
│   ├── Editor/                   # NSTextView/line numbers/highlighting
│   ├── Views/                    # Sidebar/editor/preview/AI panel/market/settings
│   └── Resources/                # preview pipeline + vendor (offline)
├── Tests/MarkNoteTests/          # tests
├── plugins-market/               # plugin library (4 theme packs + 2 view plugins)
├── scripts/build-app.sh          # package .app
└── docs/                         # plugin/theme rules, launch posts
```

## Roadmap

- Remote plugin install/update channel; plugin "command form" extension point (selected text → actions)
- More themes (dark variants)
- Mobile / cloud sync (not started)
