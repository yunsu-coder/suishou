# MarkNote (随手)

[中文](README.md) | **English**

_A macOS Markdown notes editor / local-first note-taking app. Files are the storage; AI assistant (DeepSeek) and a declarative plugin system included. SwiftUI, offline-first, Obsidian alternative._

A Markdown notes editor for macOS, built with SwiftUI + AppKit. The core idea: keep notes as plain files and avoid proprietary formats as much as possible.

> Internal codename: MarkNote. Product name in Chinese: 随手 ("as you go").

## Design

- **Notes are files**: a workspace is just a folder; each note is a `.md` or text file. Switch editors, back up, migrate, or put it in git — it all just works
- **Folders are categories**: subfolders act as categories; images, PDFs, videos and other resources are stored under `source/` by type and referenced inline
- **Trim to what you need**: write → view → save is the core. Line numbers, current-line highlight, bracket match, smart code editing, export, AI quick actions, render extensions — each has its own switch in Settings
- **AI assistant (optional)**: docked AI panel (⇧⌘A) with `@filename` file references, file read/write agent, conversation history, and summarize-to-note. Uses the DeepSeek API, built-in and ready to go

## Interface

- Tab bar sits at the same height as the window traffic lights; click to switch, × to close; the window title follows the active tab
- Left side: Workspace / Plugin Market / Settings (bottom)
- Editor is built on NSTextView; preview is a single WKWebView rendering markdown-it, KaTeX, Mermaid and highlight.js offline
- Chinese / English / Follow System; switching language takes effect after restart (same as VS Code)

## Plugins

Plugins are declarative (manifest + data files, no user code executed); enabled/disabled in the Plugin Market, off by default. Currently available:

| Category | Contents |
| --- | --- |
| Render extensions | keycap `[[⌘S]]`, mention highlight, quote beautifier, terminal-style code blocks, code-block copy button |
| Template packs | Weekly/PRD/retro, README/API/CHANGELOG, Cornell/Feynman/mistake log, emails, OKR/project plan, diary/year/habit, deploy/incident/release checklist, syllabus/lesson/exam, diet/workout/sleep |
| AI experts | Academic (paper/English writing/literature review), language (speaking/Japanese/translation), life (time/habit/emotion), coding (review/perf/algorithm), business (analysis/product/marketing), writing (copy/fiction/official docs) |
| File types | Code files (ts/js/go/rs), config files (env/ini), markup (rst/tex/org/adoc), data files (parquet/feather/delta/csv/tsv) |
| Commands | Versions / quick open / AI panel |
| Themes | Nord / Gruvbox / Ocean / Paper / Cyberpunk / Solarized / Dracula |

Plugin locations: workspace `.plugins/<id>/` or `~/Library/Application Support/MarkNote/plugins/<id>/`. Package metadata and template bodies are bilingual. See `docs/05-内置插件库.md` for details.

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
| `⌘,` | Settings (language / appearance / fonts / glass) |
| `⇧⌘A` / `⌥⌘A` | Toggle AI panel |
| `⌃⇧P` | Command palette |
| `⌃+scroll` | Layered zoom (editor=font, preview=text, otherwise=window) |
| `⌘B` | Show / hide explorer |

Help → Keyboard Shortcuts… for the full list.

## Markdown support

- Callout: `::: tip|note|warning|danger|info|details`
- Footnotes, task lists, `==mark==`, `~sub~`, `^sup^`, `++underline++`
- KaTeX math, Mermaid diagrams, code highlighting
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
├── plugins-market/               # plugin library
├── plugins-samples/              # sample packages
├── scripts/build-app.sh          # package .app
└── docs/05-内置插件库.md         # plugin docs (Chinese)
```

## Roadmap

- Remote plugin install/update channel
- More template & expert packs
- Mobile / cloud sync (not started)
