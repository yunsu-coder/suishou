#!/usr/bin/env python3
"""B3 雾青 · 亮色主题细改稿：100% 窗口 + 微调档 + 语义图标全槽位 + Markdown 语法配色。

用法: python3 scripts/make-garden-b3.py <outdir>
输出: garden-b3-window.png / garden-b3-assets.png
"""

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("gt", HERE / "make-game-themes.py")
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)

F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO

B3 = dict(
    bg="#F5F7F3", rail="#E9EDE9", sidebar="#EEF1ED", status="#E6EBE7", line="#D3DAD4",
    card="#FFFFFF", card2="#F1F4F0", sel="#DCE8E1", text="#25302B", dim="#6C7A73",
    accent="#3C7867", accent2="#A98BB2", aux="#C9A227", paper="#FFFFFF", ink="#25302B",
    **{"icon.folder": "#2C5F52", "icon.doc": "#3C7867", "icon.other": "#8A948D"})

MICRO = [
    dict(id="B3a", name="原稿", note="纸 #F5F7F3 · 主色 #3C7867", colors=dict(B3)),
    dict(id="B3b", name="更白的纸 · 主色再深一档", note="纸 #F8FAF7 · 主色 #33705F · 侧栏更分明",
         colors={**B3, "bg": "#F8FAF7", "rail": "#E7EDE8", "sidebar": "#EDF2EE", "status": "#E4EAE6",
                 "card2": "#F1F5F1", "sel": "#D9E7DF", "accent": "#33705F", "line": "#D0D8D2",
                 **{"icon.folder": "#255648", "icon.doc": "#33705F"}}),
    dict(id="B3c", name="主色偏青 · 点缀更暖", note="主色 #2E7A70 · 点缀 #D6A63C · 强调 #A88FB6",
         colors={**B3, "accent": "#2E7A70", "accent2": "#A88FB6", "aux": "#D6A63C",
                 **{"icon.folder": "#215E55", "icon.doc": "#2E7A70"}}),
]


def lum(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# ------------------------------------------------------------ 语义图标（亮色版 · 透明字形）

def g_pot(d, x, y, s, c, lw=2, opened=False):
    d.polygon([(x + s * 0.14, y + s * 0.52), (x + s * 0.86, y + s * 0.52),
               (x + s * 0.74, y + s * 0.98), (x + s * 0.26, y + s * 0.98)], outline=c, width=lw)
    d.line([(x + s * 0.10, y + s * 0.44), (x + s * 0.90, y + s * 0.44)], fill=c, width=lw)
    if opened:
        d.line([(x + s * 0.30, y + s * 0.44), (x + s * 0.42, y + s * 0.16),
                (x + s * 0.92, y + s * 0.16)], fill=c, width=lw, joint="curve")
    else:
        d.line([(x + s * 0.50, y + s * 0.44), (x + s * 0.50, y + s * 0.16)], fill=c, width=lw)
        d.ellipse([x + s * 0.24, y + s * 0.04, x + s * 0.50, y + s * 0.28], outline=c, width=max(1, lw - 1))


def g_leaf(d, x, y, s, c, lw=2):
    d.line([(x + s * 0.5, y + s * 0.98), (x + s * 0.5, y + s * 0.34)], fill=c, width=lw)
    d.arc([x + s * 0.10, y + s * 0.00, x + s * 0.90, y + s * 0.64], start=200, end=340, fill=c, width=lw)
    d.arc([x + s * 0.12, y + s * 0.32, x + s * 0.88, y + s * 0.96], start=20, end=160, fill=c, width=lw)


def g_trellis(d, x, y, s, c, lw=2):
    d.line([(x + s * 0.22, y + s * 0.06), (x + s * 0.22, y + s * 0.94)], fill=c, width=lw)
    d.line([(x + s * 0.70, y + s * 0.06), (x + s * 0.70, y + s * 0.94)], fill=c, width=lw)
    for k in (0.28, 0.56):
        d.line([(x + s * 0.10, y + s * k), (x + s * 0.86, y + s * k)], fill=c, width=max(1, lw - 1))
    d.arc([x + s * 0.46, y + s * 0.34, x + s * 0.96, y + s * 0.78], start=250, end=90, fill=c, width=lw)


def g_seedtray(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.06, y + s * 0.20, x + s * 0.94, y + s * 0.92],
                        radius=s * 0.10, outline=c, width=lw)
    for k in (0.44, 0.68):
        d.line([(x + s * 0.06, y + s * k), (x + s * 0.94, y + s * k)], fill=c, width=max(1, lw - 1))
    d.line([(x + s * 0.50, y + s * 0.20), (x + s * 0.50, y + s * 0.92)], fill=c, width=max(1, lw - 1))


def g_frame(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.06, y + s * 0.14, x + s * 0.94, y + s * 0.86],
                        radius=s * 0.08, outline=c, width=lw)
    d.polygon([(x + s * 0.18, y + s * 0.70), (x + s * 0.42, y + s * 0.40),
               (x + s * 0.64, y + s * 0.70)], outline=c, width=max(1, lw - 1))
    d.ellipse([x + s * 0.62, y + s * 0.24, x + s * 0.76, y + s * 0.38], fill=c)


def g_film(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.06, y + s * 0.18, x + s * 0.94, y + s * 0.84],
                        radius=s * 0.10, outline=c, width=lw)
    for k in (0.30, 0.52, 0.74):
        d.ellipse([x + s * 0.12, y + s * (k - 0.06), x + s * 0.22, y + s * (k + 0.04)], fill=c)
        d.ellipse([x + s * 0.78, y + s * (k - 0.06), x + s * 0.88, y + s * (k + 0.04)], fill=c)
    d.polygon([(x + s * 0.42, y + s * 0.38), (x + s * 0.66, y + s * 0.51),
               (x + s * 0.42, y + s * 0.64)], fill=c)


def g_bell(d, x, y, s, c, lw=2):
    d.polygon([(x + s * 0.28, y + s * 0.20), (x + s * 0.72, y + s * 0.20),
               (x + s * 0.86, y + s * 0.62), (x + s * 0.14, y + s * 0.62)], outline=c, width=lw)
    d.arc([x + s * 0.14, y + s * 0.44, x + s * 0.86, y + s * 0.78], start=0, end=180, fill=c, width=lw)
    d.ellipse([x + s * 0.44, y + s * 0.72, x + s * 0.56, y + s * 0.84], fill=c)
    d.line([(x + s * 0.50, y + s * 0.06), (x + s * 0.50, y + s * 0.20)], fill=c, width=lw)


def g_scroll(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.16, y + s * 0.10, x + s * 0.84, y + s * 0.90],
                        radius=s * 0.10, outline=c, width=lw)
    for k in (0.34, 0.52, 0.70):
        d.line([(x + s * 0.30, y + s * k), (x + s * 0.70, y + s * k)], fill=c, width=max(1, lw - 1))


def g_jar(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.20, y + s * 0.30, x + s * 0.80, y + s * 0.96],
                        radius=s * 0.14, outline=c, width=lw)
    d.rounded_rectangle([x + s * 0.14, y + s * 0.14, x + s * 0.86, y + s * 0.30],
                        radius=s * 0.07, outline=c, width=lw)
    for dx, dy in ((0.36, 0.62), (0.56, 0.70), (0.46, 0.82)):
        d.ellipse([x + s * dx, y + s * dy, x + s * (dx + 0.12), y + s * (dy + 0.12)], fill=c)


def g_page(d, x, y, s, c, lw=2):
    d.polygon([(x + s * 0.18, y + s * 0.06), (x + s * 0.66, y + s * 0.06),
               (x + s * 0.86, y + s * 0.28), (x + s * 0.86, y + s * 0.94),
               (x + s * 0.18, y + s * 0.94)], outline=c, width=lw)
    d.line([(x + s * 0.64, y + s * 0.10), (x + s * 0.64, y + s * 0.30),
            (x + s * 0.82, y + s * 0.30)], fill=c, width=max(1, lw - 1), joint="curve")


def g_graft(d, x, y, s, c, lw=2):
    d.line([(x + s * 0.50, y + s * 0.96), (x + s * 0.50, y + s * 0.34)], fill=c, width=lw)
    d.line([(x + s * 0.50, y + s * 0.34), (x + s * 0.30, y + s * 0.10)], fill=c, width=lw)
    d.line([(x + s * 0.50, y + s * 0.34), (x + s * 0.74, y + s * 0.14)], fill=c, width=lw)
    d.line([(x + s * 0.28, y + s * 0.60), (x + s * 0.72, y + s * 0.60)], fill=c, width=lw)
    d.ellipse([x + s * 0.60, y + s * 0.04, x + s * 0.86, y + s * 0.26], outline=c, width=max(1, lw - 1))


def g_crate(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.08, y + s * 0.24, x + s * 0.92, y + s * 0.90],
                        radius=s * 0.08, outline=c, width=lw)
    d.line([(x + s * 0.08, y + s * 0.46), (x + s * 0.92, y + s * 0.46)], fill=c, width=max(1, lw - 1))
    d.line([(x + s * 0.50, y + s * 0.46), (x + s * 0.50, y + s * 0.90)], fill=c, width=max(1, lw - 1))


def g_gear(d, x, y, s, c, lw=2):
    import math
    cx, cy, r = x + s * 0.5, y + s * 0.52, s * 0.28
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=c, width=lw)
    d.ellipse([cx - r * 0.34, cy - r * 0.34, cx + r * 0.34, cy + r * 0.34], outline=c, width=max(1, lw - 1))
    for k in range(6):
        a = math.radians(k * 60)
        d.line([(cx + math.cos(a) * r * 1.05, cy + math.sin(a) * r * 1.05),
                (cx + math.cos(a) * r * 1.52, cy + math.sin(a) * r * 1.52)], fill=c, width=lw)


def g_window(d, x, y, s, c, lw=2):
    d.rounded_rectangle([x + s * 0.06, y + s * 0.16, x + s * 0.94, y + s * 0.84],
                        radius=s * 0.10, outline=c, width=lw)
    d.line([(x + s * 0.36, y + s * 0.16), (x + s * 0.36, y + s * 0.84)], fill=c, width=max(1, lw - 1))
    for k in (0.32, 0.50, 0.68):
        d.line([(x + s * 0.14, y + s * k), (x + s * 0.28, y + s * k)], fill=c, width=max(1, lw - 1))


def g_lens(d, x, y, s, c, lw=2):
    d.ellipse([x + s * 0.06, y + s * 0.06, x + s * 0.68, y + s * 0.68], outline=c, width=lw)
    d.line([(x + s * 0.64, y + s * 0.64), (x + s * 0.94, y + s * 0.94)], fill=c, width=lw + 1)


def g_sparkle(d, x, y, s, c, lw=2):
    d.polygon([(x + s * 0.44, y + s * 0.04), (x + s * 0.56, y + s * 0.40),
               (x + s * 0.92, y + s * 0.52), (x + s * 0.56, y + s * 0.64),
               (x + s * 0.44, y + s * 1.0), (x + s * 0.32, y + s * 0.64),
               (x + s * 0.04, y + s * 0.52), (x + s * 0.32, y + s * 0.40)], fill=c)
    d.ellipse([x + s * 0.70, y + s * 0.06, x + s * 0.86, y + s * 0.22], fill=c)


def g_sundial(d, x, y, s, c, lw=2):
    d.ellipse([x + s * 0.08, y + s * 0.14, x + s * 0.92, y + s * 0.92], outline=c, width=lw)
    d.line([(x + s * 0.50, y + s * 0.53), (x + s * 0.50, y + s * 0.28)], fill=c, width=lw)
    d.line([(x + s * 0.50, y + s * 0.53), (x + s * 0.72, y + s * 0.63)], fill=c, width=lw)
    d.arc([x + s * 0.20, y + s * 0.26, x + s * 0.80, y + s * 0.86], start=190, end=320, fill=c,
          width=max(1, lw - 1))


def g_paw(d, x, y, s, c, lw=2):
    d.ellipse([x + s * 0.32, y + s * 0.44, x + s * 0.68, y + s * 0.84], fill=c)
    for dx, dy in ((0.12, 0.16), (0.38, 0.04), (0.64, 0.16)):
        d.ellipse([x + s * dx, y + s * dy, x + s * (dx + 0.22), y + s * (dy + 0.24)], fill=c)


ICONS = [
    ("folder", "文件夹", g_pot, "folder"),
    ("folder.open", "展开的文件夹", lambda d, x, y, s, c, lw=2: g_pot(d, x, y, s, c, lw, True), "folder"),
    ("file.markdown", "Markdown", g_leaf, "doc"),
    ("file.code", "代码", g_trellis, "doc"),
    ("file.data", "数据 / 表格", g_seedtray, "other"),
    ("file.image", "图片", g_frame, "other"),
    ("file.video", "视频", g_film, "other"),
    ("file.audio", "音频", g_bell, "other"),
    ("file.document", "文档", g_scroll, "doc"),
    ("file.archive", "压缩包", g_jar, "other"),
    ("file.other", "其他文件", g_page, "other"),
    ("puzzlepiece.extension", "插件", g_graft, "doc"),
    ("shippingbox", "版本 / 快照", g_crate, "other"),
    ("gearshape", "设置", g_gear, "other"),
    ("sidebar.left", "侧栏", g_window, "other"),
    ("magnifyingglass", "搜索", g_lens, "other"),
    ("sparkles", "主题 / AI", g_sparkle, "accent2"),
    ("clock.arrow.circlepath", "历史版本", g_sundial, "other"),
    ("paw", "彩蛋", g_paw, "accent2"),
]


def tier_color(c, tier):
    return {"folder": c["icon.folder"], "doc": c["icon.doc"],
            "other": c["icon.other"], "accent2": c["accent2"]}[tier]


def window_page(out, variant):
    c = variant["colors"]
    W, H = 1840, 1500
    img, d = gt.page(W, H)
    T(d, 48, 34, f"纸上花园 · 亮色细化（{variant['id']} {variant['name']}）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "100% 实际尺寸；只做亮色一套，不做暗色版。右侧是这轮改动，下方是纸底 / 主色的微调档。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 360, 46, W - 48, 90], radius=20, fill="#161C26", outline=c["accent"])
    T(d, W - 204, 68, "待人工审核 · 未安装", F(HIRA, 13), c["accent"], anchor="mm")

    win = gt.render_garden(8, palette=c, refine=True)
    gt.paste_win(img, win, 48, 150)

    blocks = [
        ("这轮改动", ["· 侧栏与图标栏各压暗一档，窗口分三层",
                      "· 正文 #25302B、次级 #6C7A73，全部过门槛",
                      "· 粉色只用于开花 / 里程碑，按钮统一主色",
                      "· 光标主色实线、选区主色 26% 叠底"]),
        ("亮色规则", ["· 不做暗色版；夜间仍跟随系统时保持同一套纸色",
                      "· 纸底不用纯白，避免长时间阅读发胀",
                      "· 强调色不超过两处同屏出现"]),
        ("下一步", ["· 字体配对（标题 / 正文 / 代码）",
                      "· 图标全槽位与 Markdown 语法配色：见另一张 garden-b3-assets",
                      "· 你点头后我做主题包并等你审核封版"]),
    ]
    y0 = 150
    for title, lines in blocks:
        h = 56 + len(lines) * 26
        d.rounded_rectangle([1400, y0, W - 48, y0 + h], radius=12, fill="#141A24", outline="#243041")
        T(d, 1418, y0 + 14, title, F(HIRA, 15, 2), c["accent"])
        for j, line in enumerate(lines):
            T(d, 1418, y0 + 44 + j * 26, line, F(HIRA, 13), "#B9C6DC")
        y0 += h + 14

    # 微调档
    T(d, 48, 980, "纸底 / 主色微调档（其余细节完全相同）", F(HIRA, 16, 2), "#DCE6FF")
    for i, v in enumerate(MICRO):
        x = 48 + i * 588
        cc = v["colors"]
        d.rounded_rectangle([x, 1016, x + 560, 1436], radius=14, fill="#111722", outline="#1F2937")
        T(d, x + 20, 1032, f"{v['id']} · {v['name']}", F(HIRA, 16, 2), "#EFF4FF")
        T(d, x + 20, 1060, v["note"], F(HIRA, 12), "#8FA0BB")
        w2 = gt.render_garden(8, palette=cc, refine=True)
        gt.paste_win(img, w2, x + 186, 1082, scale=0.28, radius=7, shadow=False)
        d.rounded_rectangle([x + 186, 1082, x + 550, 1306], radius=7, outline="#2A3648", width=1)
        for k, (key, label) in enumerate([("bg", "纸"), ("sidebar", "侧栏"), ("accent", "主色"),
                                          ("accent2", "强调"), ("aux", "点缀")]):
            yy = 1086 + k * 40
            d.rounded_rectangle([x + 20, yy, x + 54, yy + 26], radius=6, fill=cc[key], outline="#2A3648")
            T_mix(d, x + 62, yy + 4, f"{label} {cc[key].upper()}", F(MENLO, 10, 1), F(HIRA, 11), "#8FA0BB")
        T(d, x + 20, 1324, "对比度（硬门槛）", F(HIRA, 11, 2), "#B9C6DC")
        for k, (label, fg, bg, need) in enumerate([
                ("正文", cc["text"], cc["bg"], 4.5), ("次级", cc["dim"], cc["bg"], 3.5),
                ("主色", cc["accent"], cc["bg"], 4.0), ("选中行", cc["text"], cc["sel"], 4.5)]):
            col, row = k % 2, k // 2
            yy = 1348 + row * 26
            xx = x + 20 + col * 266
            T_mix(d, xx, yy, f"{label} {contrast(fg, bg):.2f}:1", F(MENLO, 11, 1), F(HIRA, 11), "#8FA0BB")
        T_mix(d, x + 20, 1404, "侧栏分层 " + f"{abs(lum(cc['sidebar']) - lum(cc['bg'])) * 100:.1f}%",
              F(MENLO, 10, 1), F(HIRA, 11), "#5F6E86")
    img.save(out)
    return out


def assets_page(out):
    c = B3
    W, H = 1840, 1240
    img, d = gt.page(W, H)
    T(d, 48, 34, "B3 雾青 · 语义图标全槽位 + Markdown 语法配色", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "亮色主题的图标是透明字形、无底板；14px 文件树尺寸可辨；颜色分三档，同档不重复。",
      F(HIRA, 15), "#93A3BE")

    # 图标表
    px, py, pw, ph = 48, 134, 1744, 520
    d.rounded_rectangle([px, py, px + pw, py + ph], radius=16, fill="#111722", outline="#1F2937")
    T(d, px + 22, py + 18, "语义图标 · 19 个槽位", F(HIRA, 17, 2), "#EFF4FF")
    T(d, px + 22, py + 46, "文件夹最深 → 文档用主色 → 其他格式中性灰绿；主题 / 彩蛋用强调色。",
      F(HIRA, 12), "#8FA0BB")
    cols = 7
    for i, (key, label, fn, tier) in enumerate(ICONS):
        col, row = i % cols, i // cols
        cx = px + 40 + col * 244
        cy = py + 96 + row * 128
        col_c = tier_color(c, tier)
        d.rounded_rectangle([cx - 14, cy - 12, cx + 200, cy + 96], radius=12, fill=c["sidebar"],
                            outline=c["line"])
        fn(d, cx, cy, 34, col_c, 2)
        fn(d, cx + 52, cy + 8, 14, col_c, 2)
        T(d, cx + 78, cy + 2, label, F(HIRA, 13), c["text"])
        T(d, cx + 78, cy + 24, key, F(MENLO, 10), c["dim"])
        T(d, cx + 78, cy + 42, col_c.upper(), F(MENLO, 10), c["dim"])
    T(d, px + 22, py + ph - 30, "提示：卡片底色就是文件树侧栏纸色（不是图标底板）；14px 为文件树真实尺寸，34px 为详情尺寸。",
      F(HIRA, 12), "#5F6E86")

    # Markdown 语法配色
    mx, my, mw, mh = 48, 682, 1090, 500
    d.rounded_rectangle([mx, my, mx + mw, my + mh], radius=16, fill=c["bg"], outline=c["line"])
    T(d, mx + 24, my + 18, "Markdown 语法配色（亮色）", F(HIRA, 17, 2), c["text"])
    T(d, mx + 24, my + 48, "秋分 · 阳台观察记", F(SONG, 26, 1), c["text"])
    d.line([(mx + 24, my + 92), (mx + mw - 24, my + 92)], fill=c["line"])
    T(d, mx + 24, my + 106, "今天风很大，我把薄荷搬到了窗边。", F(HIRA, 14), c["text"])
    T(d, mx + 24, my + 138, "重点", F(HIRA, 14, 2), c["text"])
    T(d, mx + 62, my + 138, "（粗体加重）", F(HIRA, 13), c["dim"])
    T(d, mx + 24, my + 168, "花期记录", F(HIRA, 14), c["accent"])
    T(d, mx + 112, my + 168, "链接：主色，不抢正文", F(HIRA, 12), c["dim"])
    d.rounded_rectangle([mx + 24, my + 198, mx + mw - 24, my + 240], radius=10, fill=c["card2"])
    d.rounded_rectangle([mx + 24, my + 198, mx + 29, my + 240], radius=2, fill=c["accent"])
    T(d, mx + 44, my + 208, "引用：第七朵花开了", F(HIRA, 14), c["text"])
    T(d, mx + 24, my + 254, "浇水 3 次 · 日照 4 小时", F(HIRA, 14), c["text"])
    d.ellipse([mx + 8, my + 260, mx + 16, my + 268], fill=c["accent"])
    T(d, mx + 24, my + 284, "行内代码 ", F(HIRA, 14), c["text"])
    d.rounded_rectangle([mx + 106, my + 278, mx + 206, my + 308], radius=8, fill=c["card2"])
    T_mix(d, mx + 118, my + 280, "字数 +800", F(MENLO, 12), F(HIRA, 13), c["text"])
    d.rounded_rectangle([mx + 24, my + 322, mx + mw - 24, my + 392], radius=10, fill="#EDF1EE")
    T(d, mx + 40, my + 334, "def grow(words):", F(MENLO, 13), "#2F6E5D")
    T_mix(d, mx + 40, my + 350, "    return words * 0.1  # 每 10 字长一厘米", F(MENLO, 13),
          F(HIRA, 13), "#6E7A73")
    # 表格
    d.rounded_rectangle([mx + 24, my + 406, mx + 400, my + 462], radius=10, fill=c["card"],
                        outline=c["line"])
    d.rectangle([mx + 25, my + 407, mx + 399, my + 430], fill="#EDF1EE")
    T(d, mx + 38, my + 412, "日期", F(HIRA, 12, 2), c["text"])
    T(d, mx + 190, my + 412, "字数", F(HIRA, 12, 2), c["text"])
    T(d, mx + 38, my + 436, "09-11", F(MENLO, 12), c["text"])
    T(d, mx + 190, my + 436, "1,240", F(MENLO, 12), c["text"])
    T(d, mx + 424, my + 412, "勾选框", F(HIRA, 12, 2), c["text"])
    d.rounded_rectangle([mx + 424, my + 436, mx + 440, my + 452], radius=4, fill=c["accent"])
    T(d, mx + 452, my + 434, "已完成", F(HIRA, 13), c["text"])
    T(d, mx + 560, my + 412, "高亮 / 公式 / 脚注", F(HIRA, 12, 2), c["text"])
    d.rounded_rectangle([mx + 560, my + 436, mx + 636, my + 460], radius=6, fill="#F5EFD8")
    T(d, mx + 570, my + 440, "高亮", F(HIRA, 13), "#4A3F1E")
    d.rounded_rectangle([mx + 648, my + 436, mx + 730, my + 460], radius=6, fill=c["card2"])
    T(d, mx + 658, my + 440, "E = mc²", F(MENLO, 12), c["text"])
    T(d, mx + 748, my + 440, "[1] 脚注", F(HIRA, 12), c["dim"])

    # 光标 / 选区 / 滚动条
    sx, sy, sw, sh = 1170, 682, 622, 500
    d.rounded_rectangle([sx, sy, sx + sw, sy + sh], radius=16, fill="#111722", outline="#1F2937")
    T(d, sx + 24, sy + 18, "光标 · 选区 · 滚动条 · 玻璃", F(HIRA, 17, 2), "#EFF4FF")
    rows = [
        ("编辑光标", "主色 2px 实线", c["accent"]),
        ("选区", "主色 26% 叠底", "#DCE8E1"),
        ("当前行", "纸色轻微加深", c["card2"]),
        ("查找高亮", "点缀色 24% 叠底", "#F2E9C9"),
        ("滚动条", "中性灰绿 40%", "#8A948D"),
        ("窗口玻璃", "glass = 0（不透壁纸）", c["bg"]),
    ]
    for k, (name, desc, col) in enumerate(rows):
        yy = sy + 66 + k * 62
        d.rounded_rectangle([sx + 24, yy, sx + 96, yy + 40], radius=9, fill=col, outline=c["line"])
        T(d, sx + 112, yy + 4, name, F(HIRA, 14, 2), "#EFF4FF")
        T(d, sx + 112, yy + 24, desc, F(HIRA, 12), "#8FA0BB")
    T(d, sx + 24, sy + sh - 42, "暗色版本轮不做；若以后补，会用同一套结构换纸色，不重做图标。",
      F(HIRA, 12), "#5F6E86")
    img.save(out)
    return out


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/game")
    outdir.mkdir(parents=True, exist_ok=True)
    pick = MICRO[0]
    if len(sys.argv) > 2:
        pick = next((v for v in MICRO if v["id"].lower() == sys.argv[2].lower()), pick)
    print(window_page(outdir / "garden-b3-window.png", pick))
    for v in MICRO:
        print(window_page(outdir / f"garden-b3-{v['id'].lower()}.png", v))
    print(assets_page(outdir / "garden-b3-assets.png"))


if __name__ == "__main__":
    main()
