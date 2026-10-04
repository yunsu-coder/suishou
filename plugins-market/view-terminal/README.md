# 终端（view-terminal）

内置终端面板，声明式视图插件：插件只声明「有一个 terminal 视图」，界面与执行由 app 内置渲染器提供
（与流程图、素材网格同一套机制，插件本身不执行任何代码）。

## 和 VS Code 终端一致的地方

| 能力 | 实现 |
| --- | --- |
| 完整 xterm 模拟 | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)（MIT，vendor/SwiftTerm，v1.8.0）：ANSI 真彩、光标、宽字符、备用屏、鼠标、历史滚动、选中复制 |
| 用户自己的 shell | `$SHELL -l` 登录 shell：提示符（含 p10k）、别名、函数、环境变量全都在 |
| 多终端标签 | 标签栏 + ＋新建 + 每标签独立 ✕；标题跟着 shell 的 OSC 标题更新 |
| 面板行为 | 底部停靠、拖拽调高、⌘J 开关；**关掉面板进程继续跑**，重新打开还在 |
| 配色 | 正文/底色跟随当前主题，ANSI 16 色用 VS Code 默认的 Dark+ / Light+ 两套 |
| 快捷键 | ⌘C/⌘V 复制粘贴、⌘K 清屏、Ctrl+C 中断、↑↓ 历史（终端与 shell 自身能力） |
| 运行当前文件 | ▶ 等价于在终端里敲一行 `cd 目录 && 命令`（先落盘跑最新内容，空文件会先提示） |

## 运行当前文件

选中文件后点 ▶，按扩展名自动选命令并在**文件所在目录**执行：

  | 类型 | 命令 |
  | --- | --- |
  | py | `python3` |
  | js / mjs / cjs | `node` |
  | jsx / ts / tsx | `tsx`（有则用），否则 `node` |
  | go | `go run` |
  | rs | `cargo run`（有 Cargo.toml）否则 `rustc` + 运行 |
  | c / h | `clang` 编译到临时目录后运行 |
  | cpp / cc / cxx / hpp | `c++ -std=c++17 -O2` 编译后运行 |
  | java | `java`（单文件源码启动） |
  | swift / rb / php / lua / pl / sh / bash / zsh / fish | 对应解释器 |
  | html | 交给默认浏览器打开 |
  | sql | `sqlite3` |

## 边界

- 编译产物写到系统临时目录 `marknote-run/`，不污染工作台。
- 终端里 ⌘点击链接暂不打开浏览器（⌘C 复制后自行打开）。
