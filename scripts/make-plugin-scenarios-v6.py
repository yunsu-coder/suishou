#!/usr/bin/env python3
"""场景演示 v6：素材隔离 + 可勾选跨工作台导入；卡片墙只显示标题与正文前几行。

用法: python3 scripts/make-plugin-scenarios-v6.py
"""

import importlib.util
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gt = _load("make-game-themes")
review = _load("make-misty-teal-review")
sc = _load("make-plugin-scenarios")
v3 = _load("make-plugin-scenarios-v3")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P, MD = sc.P, sc.MD
mix = sc.mix


def check(d, x, y, s, col, on=True):
    d.rounded_rectangle([x, y, x + s, y + s], radius=4,
                        fill=col if on else None, outline=col if on else P["--text-secondary"])
    if on:
        d.line([(x + s * 0.22, y + s * 0.55), (x + s * 0.42, y + s * 0.74), (x + s * 0.8, y + s * 0.26)],
               fill="#0E1512", width=2)


def sheet(title, oneline, mock, steps, rules, out, accent, icon, mock_w=780):
    W, H = 1840, 880
    img, d = gt.page(W, H)
    T(d, 48, 30, title, F(SONG, 28, 0), "#EFF4FF")
    d.rounded_rectangle([48, 76, 60, 108], radius=3, fill=accent)
    T(d, 74, 80, oneline, F(HIRA, 16, 2), P["text"])
    d.rounded_rectangle([W - 300, 40, W - 48, 82], radius=20, fill="#161C26", outline=accent)
    T(d, W - 174, 61, "第六轮细改 · 未实现", F(HIRA, 12), accent, anchor="mm")
    gt.paste_win(img, mock, 48, 124, scale=0.60, radius=10, shadow=True)
    d.rounded_rectangle([48, 124, 48 + mock_w, 124 + int(mock.height * 0.60)],
                        radius=10, outline="#2A3648", width=1)
    T(d, 872, 124, "这个包到底在干什么", F(HIRA, 15, 2), accent)
    for i, (t, detail) in enumerate(steps):
        y = 158 + i * 112
        v3.step_box(d, 872, y, 920, 100, i + 1, t, detail, accent, icon if i == 0 else None)
        if i < len(steps) - 1:
            v3.arrow(d, 1320, y + 100 + 6, 26, accent)
    top = 158 + len(steps) * 112 + 14
    h = 62 + len(rules) * 26 + 24
    d.rounded_rectangle([872, top, 1792, top + h], radius=14, fill="#111722", outline="#1F2937")
    T(d, 894, top + 18, "插件规则（写进 05-内置插件库.md）", F(HIRA, 15, 2), "#8FB8FF")
    for i, line in enumerate(rules):
        T(d, 894, top + 50 + i * 26, line, F(HIRA, 12.5), "#B9C6DC")
    img.save(out)
    print(out)


def win_base():
    return review.render_window(P).copy()


# 素材库 v6：当前工作台 + 显式导入
def scen_assets():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rounded_rectangle([14, 132, 42, 160], radius=8, fill=P["card"])
    d.rounded_rectangle([14, 178, 42, 206], radius=8, outline=P["line"])
    d.rounded_rectangle([14, 224, 42, 252], radius=8, fill=mix(P["bg"], MD["h1"], 0.28), outline=MD["h1"])
    T(d, 28, 238, "▦", F(HIRA, 13), MD["h1"], anchor="mm")
    d.rectangle([820, 0, 1300, 800], fill=P["bg"])
    d.line([(820, 0), (820, 800)], fill=P["line"])
    T(d, 846, 12, "素材 · origin", F(HIRA, 15, 2), P["text"])
    # 显式导入入口（唯一跨工作台通道）
    d.rounded_rectangle([1090, 8, 1274, 40], radius=9, fill=mix(P["bg"], MD["h2"], 0.22), outline=MD["h2"])
    T(d, 1182, 24, "从其他工作台导入…", F(HIRA, 11), MD["h2"], anchor="mm")
    T(d, 846, 40, "本工作台 source/ 资源 · 128 个（只算本工作台）", F(HIRA, 11), P["--text-secondary"])
    d.rounded_rectangle([846, 62, 1274, 92], radius=9, fill=P["card"], outline=P["line"])
    T(d, 862, 70, "搜索本工作台素材", F(HIRA, 11), P["--text-secondary"])
    for i in range(6):
        col, row = i % 3, i // 3
        x, y = 846 + col * 146, 104 + row * 128
        d.rounded_rectangle([x, y, x + 132, y + 80], radius=8,
                            fill=mix(P["bg"], MD["h3"], 0.20), outline=P["line"])
        T(d, x + 10, y + 54, f"09-1{i}-素材", F(HIRA, 10), P["text"])
        if i in (1, 4):
            d.rounded_rectangle([x + 84, y + 8, x + 124, y + 28], radius=6,
                                fill=mix(P["bg"], MD["bold"], 0.30))
            T(d, x + 104, y + 18, "引用 2", F(HIRA, 9), MD["bold"], anchor="mm")
    d.rounded_rectangle([846, 372, 1274, 456], radius=10, fill=P["card"], outline=P["line"])
    T(d, 862, 384, "09-11-手绘线稿.png", F(HIRA, 12, 2), P["text"])
    T(d, 862, 408, "本工作台内被 2 篇引用：周记 09 · 收件箱", F(HIRA, 10), P["--text-secondary"])
    d.rounded_rectangle([862, 424, 1002, 450], radius=9, fill=mix(P["bg"], MD["h1"], 0.30), outline=MD["h1"])
    T(d, 932, 437, "插入到光标处", F(HIRA, 11), MD["h1"], anchor="mm")
    T(d, 1030, 437, "⋯  在 Finder 显示", F(HIRA, 10), P["--text-secondary"])
    # 说明：隔离 + 唯一跨库通道
    d.rounded_rectangle([846, 472, 1274, 566], radius=10, fill=mix(P["bg"], MD["h2"], 0.12), outline=MD["h2"])
    T(d, 862, 482, "隔离：这里只有 origin 的素材", F(HIRA, 11.5, 2), MD["h2"])
    T(d, 862, 504, "引用计数、未引用筛选、删除提示 —— 全部只算本工作台", F(HIRA, 10), P["--text-secondary"])
    T(d, 862, 524, "需要别的库的图？走右上「从其他工作台导入…」：", F(HIRA, 10), P["--text-secondary"])
    T(d, 862, 542, "弹出可勾选列表 → 复制进本工作台（不建立跨库引用）", F(HIRA, 10), MD["h2"])
    T_mix(d, 360, 420, "![手绘线稿](img/09-11-手绘线稿.png)", F(MONO, 13), F(HIRA, 13), MD["h1"])
    d.rounded_rectangle([346, 452, 800, 502], radius=10, fill=mix(P["bg"], MD["h1"], 0.16), outline=MD["h1"])
    T(d, 362, 462, "已存入 origin/source/image/09-11-手绘线稿.png", F(HIRA, 11.5), MD["h1"])
    T(d, 362, 482, "⌘Z 撤销　·　不需要「导入」按钮（拖入即入库）", F(HIRA, 10), P["--text-secondary"])
    return win


# 导入对话框：可勾选
def scen_import():
    win = win_base()
    d = ImageDraw.Draw(win)
    # 半透明遮罩 + 弹窗
    d.rectangle([0, 0, 1300, 800], fill=mix(P["bg"], "#000000", 0.25))
    x, y, w, h = 300, 110, 700, 580
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill=P["card"], outline=P["line"])
    T(d, x + 24, y + 20, "从其他工作台导入素材", F(HIRA, 16, 2), P["text"])
    T(d, x + 24, y + 48, "勾选要用的素材 —— 会复制进 origin，不会建立跨工作台引用", F(HIRA, 11), P["--text-secondary"])
    d.rounded_rectangle([x + 24, y + 76, x + w - 24, y + 108], radius=9, fill=P["bg"], outline=P["line"])
    T(d, x + 38, y + 85, "搜索文件名（跨工作台）", F(HIRA, 11), P["--text-secondary"])
    groups = [("note · 3 个素材", [("note", "封面草图.png", True), ("note", "字段表.png", True)]),
              ("book · 2 个素材", [("book", "插图-01.png", False), ("book", "地图.png", True)])]
    yy = y + 124
    for gname, items in groups:
        T(d, x + 24, yy, gname, F(HIRA, 11, 2), P["--text-secondary"])
        yy += 26
        for ws, name, on in items:
            d.rounded_rectangle([x + 24, yy, x + w - 24, yy + 56], radius=10, fill=P["bg"], outline=P["line"])
            check(d, x + 38, yy + 18, 20, MD["h1"], on)
            d.rounded_rectangle([x + 72, yy + 8, x + 152, yy + 48], radius=6,
                                fill=mix(P["bg"], MD["h3"], 0.22))
            T(d, x + 166, yy + 12, name, F(HIRA, 12), P["text"])
            T(d, x + 166, yy + 32, f"{ws}/source/image · 240 KB", F(HIRA, 10), P["--text-secondary"])
            T(d, x + w - 40, yy + 28, "重名会自动加序号", F(HIRA, 9), P["--text-secondary"], anchor="rm")
            yy += 64
        yy += 8
    d.rounded_rectangle([x + 24, y + h - 72, x + w - 24, y + h - 20], radius=10, fill=P["bg"], outline=P["line"])
    T(d, x + 40, y + h - 60, "已勾选 3 个 · 约 720 KB", F(HIRA, 11), P["text"])
    T(d, x + 40, y + h - 40, "导入后素材属于 origin，可单独备份/搬走", F(HIRA, 10), P["--text-secondary"])
    d.rounded_rectangle([x + w - 200, y + h - 66, x + w - 116, y + h - 26], radius=9, outline=P["line"])
    T(d, x + w - 158, y + h - 46, "取消", F(HIRA, 11), P["--text-secondary"], anchor="mm")
    d.rounded_rectangle([x + w - 106, y + h - 66, x + w - 24, y + h - 26], radius=9,
                        fill=mix(P["bg"], MD["h1"], 0.30), outline=MD["h1"])
    T(d, x + w - 65, y + h - 46, "导入 3 个", F(HIRA, 11), MD["h1"], anchor="mm")
    return win


# 卡片墙 v6：标题 + 正文前几行
def scen_cards():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 12, "卡片墙 · 只显示笔记", F(HIRA, 15, 2), P["text"])
    T(d, 560, 16, "工作台 origin", F(HIRA, 10), P["--text-secondary"])
    for i, t in enumerate(["树", "卡片"]):
        x = 880 + i * 76
        d.rounded_rectangle([x, 8, x + 68, 38], radius=9,
                            fill=P["card"] if i == 1 else None, outline=None if i == 1 else P["line"])
        T(d, x + 34, 23, t, F(HIRA, 11), P["text"] if i == 1 else P["--text-secondary"], anchor="mm")
    for i, t in enumerate(["最近", "未完成", "加星"]):
        x = 1046 + i * 80
        d.rounded_rectangle([x, 8, x + 72, 38], radius=9,
                            fill=P["card"] if i == 0 else None, outline=None if i == 0 else P["line"])
        T(d, x + 36, 23, t, F(HIRA, 11), P["text"] if i == 0 else P["--text-secondary"], anchor="mm")
    d.rounded_rectangle([358, 50, 700, 78], radius=9, fill=P["card"], outline=P["line"])
    T(d, 374, 58, "预览行数：6 行 ▾（可调 3 / 6 / 10）", F(HIRA, 11), P["--text-secondary"])
    notes = [("《账目》产品设计文档", "记账这件事的边界在哪：只做「记录」，不做财务建议。第一版先解决三件事：快速记一笔、看得到的分类、月底一眼看完。输入方式优先键盘，日期自动填。",
              MD["h1"], 0.72, 1240),
             ("周记 09", "这周把主题系统收尾了，深林夜做完之后又试了一版中色的，最后放弃——中色纸天生对比度不够。下周开始做插件。",
              MD["h2"], 0.35, 860),
             ("markdown 有哪些语法", "标题、粗体、斜体、列表、任务、表格、引用、公式、脚注、Callout、代码块、时间线、GitHub 风格高亮。",
              MD["h3"], 1.0, 420),
             ("配色评审记录", "青瓷灰 / 藕荷 / 沙金 / 雾蓝 四个方向都试了，纸底带明确色相之后明显不糊了。最后还是回到深林夜。",
              MD["math"], 0.18, 680)]
    for i, (title, body, color, progress, words) in enumerate(notes):
        col, row = i % 2, i // 2
        x, y = 358 + col * 462, 92 + row * 320
        d.rounded_rectangle([x, y, x + 442, y + 300], radius=14, fill=P["card"], outline=P["line"])
        d.rounded_rectangle([x, y, x + 5, y + 300], radius=2, fill=color)
        T(d, x + 20, y + 16, title, F(HIRA, 16, 2), P["text"])
        # 正文前几行（截断显示）
        yy = y + 50
        for k, line in enumerate([body[i2:i2 + 42] for i2 in range(0, min(len(body), 168), 42)]):
            T(d, x + 20, yy + k * 24, line, F(HIRA, 12), P["--text-secondary"])
        T(d, x + 20, y + 194, "…　显示 6 行（可在顶部调成 10 行）", F(HIRA, 10), P["--text-secondary"])
        d.rounded_rectangle([x + 20, y + 222, x + 424, y + 230], radius=4, fill=P["card2"])
        d.rounded_rectangle([x + 20, y + 222, x + 20 + int(404 * progress), y + 230], radius=4, fill=color)
        T(d, x + 20, y + 238, f"上次读到 {int(progress * 100)}%　·　{words:,} 字", F(HIRA, 10), P["--text-secondary"])
        for j, (label, c2) in enumerate([("继续写", color), ("加星", P["--text-secondary"]), ("归档", P["--text-secondary"])]):
            bx = x + 20 + j * 96
            d.rounded_rectangle([bx, y + 262, bx + 84, y + 286], radius=8, outline=c2 if j == 0 else P["line"])
            T(d, bx + 42, y + 274, label, F(HIRA, 10), c2 if j == 0 else P["--text-secondary"], anchor="mm")
    return win


def main():
    outdir = ROOT / "docs/proposals/plugins"
    sheet("场景 ① · 素材库 v6（隔离 + 可勾选导入）",
          "一句话：面板里只有当前工作台的素材；别的库的图，走右上「从其他工作台导入…」勾选后复制进来。",
          scen_assets(),
          [("拖入 / 粘贴（唯一日常触发）",
            ["存进「当前工作台 / source/image」，按「日期-描述」命名，可 ⌘Z 撤销"]),
           ("面板只认当前工作台",
            ["引用计数、未引用筛选、删除提示全部只算本工作台；没有「全部工作台」视图"]),
           ("要别的库的图 → 勾选导入",
            ["弹窗按工作台分组、可多项勾选；导入 = 复制进本工作台，不建立跨库引用"])],
          ["隔离：每个工作台独立，素材不自动跟随、不全局共享",
           "唯一跨库通道：用户显式勾选导入（复制，不改原库）",
           "只读：复用现有 source/ 扫描；只写：本工作台 source/",
           "已去掉「一键整理历史图」——不做批量改名"],
          outdir / "v6-assets.png", MD["h1"], v3.icon_file)
    sheet("场景 ② · 从其他工作台导入（可勾选）",
          "一句话：唯一允许跨工作台的动作，就是这张勾选清单——复制进来，不动原库。",
          scen_import(),
          [("点右上「从其他工作台导入…」",
            ["弹窗按工作台分组（note / book …），每项带缩略图、路径与大小"]),
           ("勾选你要的那几张",
            ["支持搜索；重名自动加序号；底部实时显示「已勾选 3 个 · 约 720 KB」"]),
           ("导入 = 复制进当前工作台",
            ["导入后这些素材属于 origin，可单独备份/搬走；原工作台完全不受影响"])],
          ["禁止：跨工作台的引用（会导致搬走一个库就断图）",
           "禁止：自动同步、自动合并素材（只做一次性复制）",
           "原库只读：导入过程绝不修改来源工作台",
           "冲突：同名自动加序号，不覆盖任何已有文件"],
          outdir / "v6-import.png", MD["h2"], v3.icon_grid)
    sheet("场景 ③ · 卡片墙 v6（标题 + 正文前几行）",
          "一句话：卡片不再放封面图，就是「标题 + 正文前几行」，行数可在顶部调（3 / 6 / 10）。",
          scen_cards(),
          [("侧栏顶部切「树 / 卡片」",
            ["只显示当前工作台的笔记；工作台切换在设置里"]),
           ("卡片 = 标题 + 正文前几行",
            ["默认 6 行，顶部下拉可调 3 / 6 / 10 行；标题左边一条目录色"]),
           ("底部一行元信息 + 悬浮操作",
            ["字数、上次读到 %；悬浮出现 继续写 / 加星 / 归档"])],
          ["只读：复用目录索引与正文缓存（不额外扫描）",
           "不做封面图：卡片内容全部来自笔记正文",
           "不写：不移动、不改名、不改笔记内容",
           "卸载即干净：切回文件树，一切照旧"],
          outdir / "v6-cards.png", MD["h3"], v3.icon_window)


if __name__ == "__main__":
    main()
