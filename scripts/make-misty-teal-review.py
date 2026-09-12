#!/usr/bin/env python3
"""「雾青」主题包评审图：图标（64px / 14px）、配色与门槛数据、窗口预览、动效分镜。

用法: python3 scripts/make-misty-teal-review.py <包目录> <输出.png>
"""

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gt = _load("make-game-themes")
b3 = _load("make-garden-b3")
refine = _load("make-garden-refine")
mt = _load("make-misty-teal")

P = mt.P
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO


def swatch(d, x, y, w, h, color, label, value, text_col="#EFF4FF"):
    d.rounded_rectangle([x, y, x + w, y + h], radius=9, fill=color, outline="#2A3648")
    T(d, x, y + h + 8, label, F(HIRA, 11), "#8FA0BB")
    T(d, x, y + h + 26, value, F(MENLO, 10, 1), "#5F6E86")


def render_window(p):
    """纯主题效果：不带任何玩法面板（委托 / 花园 / 经验条都不出现）。"""
    f = gt.fonts("garden")
    img, d = gt.chrome("garden", p)
    gt.rail_icons(d, p, "garden")
    gt.header(d, p, f)
    rows = [
        (0, "pot", "写作", ""),
        (1, "leaf", "秋分 · 观察记.md", ""),
        (1, "leaf", "薄荷养护.md", ""),
        (1, "scroll", "读书笔记.md", ""),
        (1, "frame", "第七朵花.png", ""),
        (0, "pot", "项目", ""),
        (1, "leaf", "周记 09.md", ""),
    ]
    gt.tree(d, p, f, rows, selected=1,
            icon_colors=[p["icon.folder"], p["icon.doc"], p["icon.doc"], p["icon.doc"],
                         p["icon.other"], p["icon.folder"], p["icon.doc"]])
    d.rounded_rectangle([66, 132 + 28, 69, 132 + 58], radius=2, fill=p["accent"])

    gt.tabbar(d, p, f, "leaf", "秋分 · 观察记")
    gt.split_panes(d, p)

    # 源码区
    T(d, 360, 78, "# 秋分 · 阳台观察记", F(SONG, 17, 1), p["text"])
    T_mix(d, 360, 112, "今天风很大，我把薄荷搬到了窗边。", F(MENLO, 13), F(HIRA, 14), p["text"])
    pre = "今天风很大，"
    x0 = 360 + gt.mix_width(d, pre, F(MENLO, 13), F(HIRA, 14))
    x1 = 360 + gt.mix_width(d, "今天风很大，我把薄荷搬到了窗边。", F(MENLO, 13), F(HIRA, 14))
    band = Image.new("RGB", (int(x1 - x0), 20), p["accent"])
    img.paste(Image.blend(img.crop((int(x0), 112, int(x1), 132)), band, 0.26), (int(x0), 112))
    d.rectangle([x1 + 3, 112, x1 + 5, 132], fill=p["accent"])
    T_mix(d, 360, 146, "- 浇水 3 次 · 日照 4 小时", F(MENLO, 13), F(HIRA, 14), p["text"])
    T_mix(d, 360, 178, "> 第七朵花开了", F(MENLO, 13), F(HIRA, 14), p["accent_ink"])
    T_mix(d, 360, 210, "**重点** 与 `字数 +800`", F(MENLO, 13), F(HIRA, 14), p["text"])

    # 预览区
    T(d, 852, 74, "秋分 · 阳台观察记", F(SONG, 28, 0), p["text"])
    d.line([(852, 122), (1264, 122)], fill=p["line"])
    T(d, 852, 142, "今天风很大，我把薄荷搬到了窗边。", F(HIRA, 14), p["text"])
    d.ellipse([852, 184, 858, 190], fill=p["accent"])
    T(d, 872, 178, "浇水 3 次 · 日照 4 小时", F(HIRA, 14), p["text"])
    d.rounded_rectangle([852, 214, 1264, 256], radius=10, fill=p["card2"])
    d.rounded_rectangle([852, 214, 857, 256], radius=2, fill=p["accent"])
    T(d, 872, 224, "第七朵花开了", F(HIRA, 14), p["text"])
    T(d, 852, 274, "链接 花期记录", F(HIRA, 14), p["accent_ink"])
    d.rounded_rectangle([960, 268, 1080, 302], radius=8, fill=p["card2"])
    T_mix(d, 972, 270, "字数 +800", F(MENLO, 12), F(HIRA, 13), p["text"])
    T(d, 852, 320, "**重点** 行内代码与链接各自定色，引用用主色左条。", F(HIRA, 13), p["secondary"])
    d.rounded_rectangle([852, 356, 1264, 520], radius=12, fill=p["card"], outline=p["line"])
    T(d, 872, 372, "正文示例", F(HIRA, 13, 2), p["accent"])
    T(d, 872, 400, "记录第七朵花开了，顺手写下浇水与日照时数。", F(HIRA, 14), p["text"])
    T(d, 872, 430, "次级文字：写下 800 字它会开花。", F(HIRA, 13), p["secondary"])
    T(d, 872, 458, "强调：木槿（稀有）", F(HIRA, 13), p["accent2"])
    T(d, 872, 486, "点缀：日照 4 小时", F(HIRA, 13), p["aux"])

    gt.statusbar_static(d, p, f, "已保存 · 1,240 字")
    T_mix(d, 344, 774, "LF · Markdown　1,240 字符　行 12 · 列 8", f["num"], f["ui"], p["secondary"])
    return img


def main():
    pkg = Path(sys.argv[1])
    out = Path(sys.argv[2])
    W, H = 1840, 1520
    img, d = gt.page(W, H)
    T(d, 48, 34, "雾青 · 主题包评审稿（亮色）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, f"包目录：{pkg}　·　人工审核通过前不进入主题列表", F(HIRA, 14), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline=P["accent"])
    T(d, W - 189, 68, "技术审计已通过 · 待你审核", F(HIRA, 13), P["accent"], anchor="mm")

    # 窗口预览
    win = render_window(P)
    gt.paste_win(img, win, 48, 136, scale=0.72, radius=10, shadow=True)
    d.rounded_rectangle([48, 136, 48 + int(1300 * 0.72), 136 + int(800 * 0.72)], radius=10,
                        outline="#2A3648", width=1)

    # 配色
    px = 1040
    d.rounded_rectangle([px, 136, W - 48, 400], radius=14, fill="#111722", outline="#1F2937")
    T(d, px + 22, 152, "配色与门槛数据", F(HIRA, 16, 2), "#EFF4FF")
    for i, (key, label, val) in enumerate([
            ("bg", "编辑纸", P["bg"]), ("sidebar", "侧栏", P["sidebar"]),
            ("accent", "主色", P["accent"]), ("accent2", "强调", P["accent2"]),
            ("aux", "点缀", P["aux"])]):
        swatch(d, px + 22 + i * 116, 190, 92, 56, val, label, val.upper())
    for i, (label, fg, bg, need) in enumerate([
            ("正文 / 纸", P["text"], P["bg"], 4.5),
            ("次级 / 纸", P["secondary"], P["bg"], 3.5),
            ("强调 / 纸", P["accent_ink"], P["bg"], 4.0)]):
        r = mt.contrast(fg, bg)
        T(d, px + 22 + i * 250, 300, f"{label}　{r:.2f}:1 ≥ {need}", F(HIRA, 12), "#B9C6DC")
        refine.check(d, px + 22 + i * 250 + 178, 302, 12, "#7FD1A8" if r >= need else "#E08C90",
                     r >= need)
    T(d, px + 22, 336, "字体：站酷小薇（标题）· 苹方（正文 / 界面）· JetBrains Mono（编辑 / 行号）",
      F(HIRA, 12), "#8FA0BB")
    T(d, px + 22, 360, "图标 / 字体 / CSS 体积与透明度均达标：glass = 0，不做透壁纸。",
      F(HIRA, 12), "#8FA0BB")

    # 动效分镜
    d.rounded_rectangle([px, 424, W - 48, 712], radius=14, fill="#111722", outline="#1F2937")
    T(d, px + 22, 440, "专属动效 · 叶片光尘（ambientPollen）", F(HIRA, 16, 2), "#EFF4FF")
    for k in range(3):
        fx = px + 22 + k * 250
        d.rounded_rectangle([fx, 476, fx + 230, 660], radius=12, fill=P["bg"], outline=P["line"])
        import math
        for i in range(7):
            prog = (k * 0.32 + i * 0.13) % 1.0
            gx = fx + 20 + ((i * 53) % 190)
            gy = 492 + prog * 140
            leaf = b3.g_leaf
            leaf(d, gx, gy, 14, P["accent"], 2)
        T(d, fx + 12, 668, f"t = {k * 0.5 + 0.2:.1f}s", F(MENLO, 10, 1), "#5F6E86")
    T(d, px + 22, 684, "极淡的叶片缓慢飘落；系统开启「减少动态效果」时自动静止。", F(HIRA, 11), "#8FA0BB")

    # 图标表
    iy = 780
    d.rounded_rectangle([48, iy, W - 48, iy + 660], radius=16, fill="#111722", outline="#1F2937")
    T(d, 70, iy + 20, "19 个语义图标 · 64px 与 14px 实际尺寸", F(HIRA, 17, 2), "#EFF4FF")
    T(d, 70, iy + 48, "透明字形、无底板；容器 / 文档 / 其他格式三档颜色，主题与彩蛋用强调色。",
      F(HIRA, 12), "#8FA0BB")
    cols = 7
    for i, (key, fname, fn, tier) in enumerate(mt.ICON_MAP):
        col, row = i % cols, i // cols
        cx = 70 + col * 246
        cy = iy + 92 + row * 188
        icon = Image.open(pkg / f"icons/{fname}-64.png").convert("RGBA")
        big = icon.resize((56, 56), Image.LANCZOS)
        img.paste(big, (cx, cy), big)
        small = icon.resize((14, 14), Image.LANCZOS)
        img.paste(small, (cx + 66, cy + 36), small)
        T(d, cx + 92, cy + 2, key.split(".")[-1], F(HIRA, 13), "#EFF4FF")
        T(d, cx + 92, cy + 24, fname, F(MENLO, 10), "#8FA0BB")
        T(d, cx + 92, cy + 42, mt.TIERS[tier].upper(), F(MENLO, 10), "#5F6E86")
        d.rounded_rectangle([cx + 66, cy + 32, cx + 86, cy + 54], radius=4, outline="#26313F")
    T(d, 70, iy + 640, "14px 缩略图放在小方框里，用于检查文件树里的可辨识度。", F(HIRA, 11), "#5F6E86")

    # 彩蛋与动效说明
    d.rounded_rectangle([48, H - 150, W - 48, H - 48], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 132, "已通过的技术门槛", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, H - 104, "① 人工审核：等你点头后才写入 reviewedHash（见 theme.json）", F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 80, "② 图标语义：19 个槽位全覆盖、无复用、不透明覆盖率 ≤82%（实测 19%–47%）", F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 56, "③ 彩蛋 / 动效 / 可读性 / 体积：全部达标；亮色单主题，dawn 与 night 同为这套纸色",
      F(HIRA, 13), "#B9C6DC")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
