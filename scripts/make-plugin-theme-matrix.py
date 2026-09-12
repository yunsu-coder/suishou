#!/usr/bin/env python3
"""插件主题适配矩阵：同一个插件界面（卡片墙）在四套主题下各渲染一遍。

用法: python3 scripts/make-plugin-theme-matrix.py
输出: docs/proposals/plugins/theme-matrix.png
"""

import importlib.util
import re
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
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")

THEMES = [
    ("theme-misty-teal", "雾青", "亮色", "站酷小薇 / 苹方 / JetBrains Mono"),
    ("theme-sumi-paper", "墨纸", "亮色", "马善政楷书 / 站酷小薇 / JetBrains Mono"),
    ("theme-bubble-pop", "Bubble Pop", "亮色", "Silkscreen + 融合像素 / JetBrains Mono"),
    ("theme-forest-night", "深林夜", "暗色", "马善政楷书 / 苹方 / JetBrains Mono"),
]


def vars_of(css):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[a-z0-9-]+)\s*:\s*([^;]+);", css)}


def mix(a, b, t):
    ca, cb = gt.PALETTES["guild"]["bg"], gt.PALETTES["guild"]["bg"]
    def hexc(v):
        v = v.strip().lstrip("#")
        if len(v) == 3:
            v = "".join(c * 2 for c in v)
        return tuple(int(v[i:i + 2], 16) for i in (0, 2, 4))
    if a.startswith("rgba"):
        p = [x.strip() for x in a[5:-1].split(",")]
        base = hexc(b)
        al = float(p[3])
        ca = tuple(round(int(p[i]) * al + base[i] * (1 - al)) for i in range(3))
    else:
        ca = hexc(a)
    cb = hexc(b)
    return "#%02X%02X%02X" % tuple(round(ca[i] * (1 - t) + cb[i] * t) for i in range(3))


def palette_for(pkg):
    css = (ROOT / "plugins-market" / pkg / "theme.css").read_text(encoding="utf-8")
    v = vars_of(css)
    md = {k[5:]: val for k, val in v.items() if k.startswith("--md-")}
    luc = lambda c: gt.PALETTES["guild"]["bg"]
    pal = dict(
        bg=v["--bg"], sidebar=v.get("--sidebar", mix(v["--bg"], v["--text"], 0.04)),
        rail=mix(v["--bg"], v["--text"], 0.07), status=mix(v["--bg"], v["--text"], 0.05),
        card=v.get("--surface", mix(v["--bg"], v["--text"], 0.03)),
        card2=v.get("--code-bg", mix(v["--bg"], v["--text"], 0.06)),
        sel=mix(v.get("--sel", v["--accent"]), v["--bg"], 0.82),
        line=mix(v.get("--border", "#888888"), v["--bg"], 0.35),
        text=v["--text"], dim=v.get("--text-secondary", v["--text"]),
        secondary=v.get("--text-secondary", v["--text"]),
        accent=v["--accent"], accent_ink=v.get("--accent-ink", v["--accent"]),
        accent2=md.get("h3", v["--accent"]), aux=md.get("italic", v["--accent"]),
        paper=v.get("--surface", v["--bg"]), ink=v["--text"],
        **{"icon.folder": md.get("list", v["--accent"]), "icon.doc": md.get("link", v["--accent"]),
           "icon.other": md.get("quote", v["--text-secondary"])})
    return pal, md, v


def cardwall(pal, md):
    win = review.render_window(pal).copy()
    d = ImageDraw.Draw(win)
    t = pal["text"]
    sec = pal["secondary"]
    d.rectangle([330, 0, 1300, 800], fill=pal["bg"])
    T(d, 358, 12, "卡片墙 · 只显示笔记", F(HIRA, 15, 2), t)
    T(d, 560, 16, "工作台 origin", F(HIRA, 10), sec)
    for i, label in enumerate(["树", "卡片"]):
        x = 880 + i * 76
        d.rounded_rectangle([x, 8, x + 68, 38], radius=9,
                            fill=pal["card"] if i == 1 else None,
                            outline=None if i == 1 else pal["line"])
        T(d, x + 34, 23, label, F(HIRA, 11), t if i == 1 else sec, anchor="mm")
    for i, label in enumerate(["最近", "未完成", "加星"]):
        x = 1046 + i * 80
        d.rounded_rectangle([x, 8, x + 72, 38], radius=9,
                            fill=pal["card"] if i == 0 else None,
                            outline=None if i == 0 else pal["line"])
        T(d, x + 36, 23, label, F(HIRA, 11), t if i == 0 else sec, anchor="mm")
    d.rounded_rectangle([358, 50, 700, 78], radius=9, fill=pal["card"], outline=pal["line"])
    T(d, 374, 58, "预览行数：6 行 ▾（可调 3 / 6 / 10）", F(HIRA, 11), sec)
    notes = [("《账目》产品设计文档",
              "记账这件事的边界在哪：只做「记录」，不做财务建议。第一版先解决三件事：快速记一笔、看得到的分类、月底一眼看完。",
              md.get("h1", t), 0.72, 1240),
             ("周记 09", "这周把主题系统收尾了，深林夜做完之后又试了一版中色的，最后放弃——中色纸天生对比度不够。",
              md.get("h2", t), 0.35, 860),
             ("markdown 有哪些语法", "标题、粗体、斜体、列表、任务、表格、引用、公式、脚注、Callout、代码块、时间线。",
              md.get("h3", t), 1.0, 420),
             ("配色评审记录", "青瓷灰 / 藕荷 / 沙金 / 雾蓝 四个方向都试了，纸底带明确色相之后明显不糊了。",
              md.get("math", t), 0.18, 680)]
    for i, (title, body, color, progress, words) in enumerate(notes):
        col, row = i % 2, i // 2
        x, y = 358 + col * 462, 92 + row * 320
        d.rounded_rectangle([x, y, x + 442, y + 300], radius=14, fill=pal["card"], outline=pal["line"])
        d.rounded_rectangle([x, y, x + 5, y + 300], radius=2, fill=color)
        T(d, x + 20, y + 16, title, F(HIRA, 16, 2), t)
        yy = y + 50
        for k, line in enumerate([body[j:j + 42] for j in range(0, min(len(body), 168), 42)]):
            T(d, x + 20, yy + k * 24, line, F(HIRA, 12), sec)
        T(d, x + 20, y + 194, "…　显示 6 行（可在顶部调成 10 行）", F(HIRA, 10), sec)
        d.rounded_rectangle([x + 20, y + 222, x + 424, y + 230], radius=4, fill=pal["card2"])
        d.rounded_rectangle([x + 20, y + 222, x + 20 + int(404 * progress), y + 230], radius=4, fill=color)
        T(d, x + 20, y + 238, f"上次读到 {int(progress * 100)}%　·　{words:,} 字", F(HIRA, 10), sec)
        for j, (label, c2) in enumerate([("继续写", color), ("加星", sec), ("归档", sec)]):
            bx = x + 20 + j * 96
            d.rounded_rectangle([bx, y + 262, bx + 84, y + 286], radius=8,
                                outline=c2 if j == 0 else pal["line"])
            T(d, bx + 42, y + 274, label, F(HIRA, 10), c2 if j == 0 else sec, anchor="mm")
    return win


def main():
    out = ROOT / "docs/proposals/plugins/theme-matrix.png"
    W, H = 1840, 1180
    img, d = gt.page(W, H)
    T(d, 48, 30, "插件主题适配 · 同一个界面 × 四套主题", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 80, "规则：插件界面不允许写死颜色/字体——纸底、面板、文字、边框、强调色、标题色、字体、动效时长全部取当前主题。下面是同一张卡片墙在四主题下的样子。",
      F(HIRA, 14), "#93A3BE")
    d.rounded_rectangle([W - 330, 40, W - 48, 82], radius=20, fill="#161C26", outline="#7FD1C0")
    T(d, W - 189, 61, "验收图 · 每个插件都要有", F(HIRA, 12), "#7FD1C0", anchor="mm")
    for i, (pkg, name, tone, fonts) in enumerate(THEMES):
        pal, md, v = palette_for(pkg)
        col, row = i % 2, i // 2
        x, y = 48 + col * 892, 130 + row * 520
        d.rounded_rectangle([x, y, x + 860, y + 490], radius=16, fill="#111722", outline="#1F2937")
        T(d, x + 22, y + 16, f"{name} · {tone}", F(HIRA, 17, 2), "#EFF4FF")
        T(d, x + 22, y + 44, fonts, F(HIRA, 11), "#8FA0BB")
        win = cardwall(pal, md)
        gt.paste_win(img, win, x + 22, y + 72, scale=0.35, radius=8, shadow=False)
        d.rounded_rectangle([x + 22, y + 72, x + 22 + 455, y + 72 + 280], radius=8,
                            outline="#2A3648", width=1)
        # 取色说明
        sx = x + 500
        items = [("纸底 --bg", v["--bg"]), ("面板 --surface", v.get("--surface", pal["card"])),
                 ("正文 --text", v["--text"]), ("次级 --text-secondary", v.get("--text-secondary", pal["secondary"])),
                 ("主色 --accent", v["--accent"]), ("标题 --h1", md.get("h1", v["--accent"]))]
        for k, (label, color) in enumerate(items):
            yy = y + 84 + k * 46
            d.rounded_rectangle([sx, yy, sx + 54, yy + 30], radius=7, fill=color, outline="#2A3648")
            T(d, sx + 66, yy + 3, label, F(HIRA, 11), "#B9C6DC")
            T(d, sx + 66, yy + 19, color.upper(), F(MONO, 9), "#6F7E96")
        T(d, sx, y + 372, "卡片里的目录色条 =", F(HIRA, 11), "#8FA0BB")
        for k, key in enumerate(["h1", "h2", "h3", "math"]):
            c = md.get(key, pal["accent"])
            d.rounded_rectangle([sx + 130 + k * 44, y + 366, sx + 166 + k * 44, y + 392], radius=6, fill=c)
        T(d, sx, y + 406, "按钮/进度/悬浮色 = 目录色；文字与边框 = 主题的 --text / --border", F(HIRA, 10), "#6F7E96")
        T(d, sx, y + 428, "字体 = 主题的标题/正文字体；动效时长 = 主题 motion.durationMs", F(HIRA, 10), "#6F7E96")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
