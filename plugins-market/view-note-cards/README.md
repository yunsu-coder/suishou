# 卡片墙 · Note Cards（视图插件）

把**当前工作台**的笔记摊成按天分组的卡片墙，用于回顾；**只读**，不移动/改名/改写任何文件。

## 声明（views.json）

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `type` | `noteCards` | app 内置渲染器，插件不提供代码 |
| `scope` | `workspace` | 只读当前工作台；读笔记内容的视图不允许 `global`（扫描阶段拦截） |
| `placement` | `main` | 占主区域，侧栏出现「树 / 卡片」切换 |
| `options.previewLines` | `6` | 卡片正文行数（3 / 6 / 10 可调） |
| `options.actions` | `open` `star` | 悬浮动作；星标只存本机偏好 |

## 主题适配

卡片颜色与字体全部取当前主题变量（`--bg` / `--surface` / `--text` / `--text-secondary` / `--accent`），
不写死任何色值——四套主题（雾青 / 墨纸 / Bubble Pop / 深林夜）下自动适配。
