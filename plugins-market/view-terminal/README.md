# 终端（view-terminal）

内置终端面板，声明式视图插件：插件只声明「有一个 terminal 视图」，界面与执行由 app 内置渲染器提供
（与流程图、素材网格同一套机制，插件本身不执行任何代码）。

## 用法

- **开关**：⌘J，或侧栏功能栏的终端图标；面板顶部可拖拽调高，关闭面板即结束会话。
- **运行当前文件**：选中文件后点 ▶，按扩展名自动选命令并在**文件所在目录**执行：

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

- **自由命令**：底部输入行直接敲命令，↑↓ 翻历史；`cd`、环境变量在会话内保持。
- **中断**：运行中点 ⏹ 发 ^C；1.2 秒仍未结束会补 SIGINT。

## 边界

- 输出会去掉 ANSI 控制码（颜色/光标控制不还原），进度条的覆盖式刷新只保留最后一段。
- 编译产物写到系统临时目录 `marknote-run/`，不污染工作台。
- 需要登录态/交互输入的程序（sudo、ssh、vim 等）不保证可用。

## 会话是怎么起的（踩过的坑都在这里）

- **真 PTY，但不是登录 shell**：会话由 `/usr/bin/script` 分配伪终端（^C 才能送到前台进程组），
  内部跑 `zsh -f +o zle` —— 不读用户的 `.zshrc`、关掉行编辑器。
  原因：oh-my-zsh + powerlevel10k 会在每次提示符处重绘整块 powerline 并往外发 OSC 转义，
  在面板里就是"命令重复三遍 + `]7;file://…` 乱码"。面板要的是能稳定跑命令。
- **PATH 由面板注入**：`~/.cargo/bin`、`~/go/bin`、`~/.local/bin`、`~/.pyenv/shims`、
  `/opt/homebrew/bin`（含 sbin）与 `/usr/local/bin`，再接 app 原有 PATH，
  所以 `node` / `python3` / `brew` 这类工具照常能找到；别名与自定义函数不加载。
- **`stty -echo` + 面板自己回显**：终端回显会把内部的退出码哨兵一起显示，所以关掉回显，
  由面板打印一行 `❯ 命令`。
- **哨兵要拆成两段字面量**：`echo "__MARKNOTE""_EXIT__$?"` —— 终端回显会把整行原样抄回来，
  只有命令输出里才会拼成完整哨兵；否则握手会被"回声"提前触发。
