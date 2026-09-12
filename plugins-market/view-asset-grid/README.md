# 素材网格 · Asset Grid（视图插件）

侧栏第三格里的素材面板：**只看当前工作台** `source/` 下的资源。

## 声明（views.json）

| 字段 | 值 | 说明 |
| --- | --- | --- |
| `type` | `assetGrid` | app 内置渲染器 |
| `scope` | `workspace` | 读工作台资源的视图不允许 `global`（扫描阶段拦截） |
| `placement` | `panel` | 侧栏面板（不占编辑宽度） |
| `options.dirs` | `["source"]` | 扫描范围 |
| `options.showRefCount` | `true` | 显示「引用 N / 未引用」（只算当前工作台） |
| `options.allowImport` | `true` | 预留：跨工作台**可勾选导入**（下一步实现） |

## 隔离

- 只读当前工作台；不扫描、不聚合其他工作台（禁止跨库引用）
- 不做批量改名；删除仍走应用原有的删除入口（带确认）
- 插入 = 写一行短引用到光标处（`img/xxx.png`），不改素材文件本身
