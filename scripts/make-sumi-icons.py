#!/usr/bin/env python3
"""生成 SUMI PAPER 主题的扁平墨线图标（16/64px，透明背景）。

工艺：4x 超采样；纸色实底 + 墨色描边/线条 + 朱砂点缀。无渐变、无像素。
用法: python3 scripts/make-sumi-icons.py <输出目录>
"""

import os
import sys

from PIL import Image, ImageDraw

S = 4
CANVAS = 64 * S
INK = "#1C1A17"
PAPER = "#F5EFE3"
SEAL = "#C8442E"

# 文件/文件夹颜色层级：同一种墨线工艺，用不同重点色区分类型。
ACCENTS = {
    "folder.open": "#C8442E",
    "file.markdown": "#3B5BA5",
    "file.code": "#6A3BD6",
    "file.data": "#3F6B4F",
    "file.image": "#2F7FA0",
    "file.video": "#C45A1E",
    "file.audio": "#B03A6E",
    "file.document": "#6B6257",
    "file.archive": "#8A6A2E",
    "file.other": "#6F6A63",
}

# 文件类型与文件夹图标：透明墨线字形、无纸色底板。
GLYPHS_ONLY = {
    "folder", "folder.open",
    "file.markdown", "file.code", "file.data", "file.image",
    "file.video", "file.audio", "file.document", "file.archive", "file.other",
}


def make_icon(name, scale=1):
    img = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if name not in GLYPHS_ONLY:
        d.rounded_rectangle([2 * S, 2 * S, CANVAS - 2 * S, CANVAS - 2 * S], radius=17 * S,
                            fill=PAPER, outline=INK, width=3 * S)
    w = 6 * S if name in GLYPHS_ONLY else 5 * S
    c = CANVAS // 2
    accent = ACCENTS.get(name, SEAL)
    stroke = accent if name in GLYPHS_ONLY else INK

    if name == "folder":
        d.rounded_rectangle([15 * S, 25 * S, 49 * S, 46 * S], radius=4 * S, outline=stroke, width=w)
        d.rounded_rectangle([15 * S, 19 * S, 31 * S, 28 * S], radius=3 * S, outline=stroke, width=w)
        d.ellipse([43 * S, 14 * S, 50 * S, 21 * S], fill=accent)
    elif name == "plugin":
        d.rounded_rectangle([24 * S, 19 * S, 40 * S, 43 * S], radius=6 * S, outline=stroke, width=w)
        d.line([(28 * S, 19 * S), (28 * S, 12 * S)], fill=stroke, width=w)
        d.line([(36 * S, 19 * S), (36 * S, 12 * S)], fill=stroke, width=w)
        d.line([(32 * S, 43 * S), (32 * S, 51 * S)], fill=stroke, width=w)
        d.ellipse([43 * S, 14 * S, 50 * S, 21 * S], fill=accent)
    elif name == "settings":
        d.ellipse([c - 13 * S, c - 13 * S, c + 13 * S, c + 13 * S], outline=stroke, width=w)
        for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
            d.line([(c + dx * 18 * S, c + dy * 18 * S), (c + dx * 25 * S, c + dy * 25 * S)], fill=stroke, width=w)
        d.ellipse([c - 5 * S, c - 5 * S, c + 5 * S, c + 5 * S], fill=accent)
    elif name == "sidebar":
        d.rounded_rectangle([13 * S, 17 * S, 51 * S, 47 * S], radius=5 * S, outline=stroke, width=w)
        d.line([(26 * S, 17 * S), (26 * S, 47 * S)], fill=stroke, width=w)
        d.rectangle([17 * S, 23 * S, 22 * S, 28 * S], fill=accent)
        d.ellipse([17 * S, 33 * S, 21 * S, 37 * S], fill=stroke)
    elif name == "search":
        d.ellipse([15 * S, 14 * S, 40 * S, 39 * S], outline=stroke, width=w)
        d.line([(36 * S, 35 * S), (49 * S, 48 * S)], fill=stroke, width=w)
        d.ellipse([41 * S, 13 * S, 47 * S, 19 * S], fill=accent)
    elif name == "branch":
        d.ellipse([13 * S, 15 * S, 24 * S, 26 * S], outline=stroke, width=w)
        d.ellipse([40 * S, 15 * S, 51 * S, 26 * S], fill=accent)
        d.ellipse([26 * S, 40 * S, 37 * S, 51 * S], outline=stroke, width=w)
        d.line([(18 * S, 26 * S), (18 * S, 34 * S), (32 * S, 45 * S)], fill=stroke, width=w)
        d.line([(45 * S, 26 * S), (45 * S, 34 * S), (32 * S, 41 * S)], fill=stroke, width=w)
    elif name == "sparkle":
        d.polygon([(c, 11 * S), (c + 7 * S, c - 7 * S), (53 * S, c),
                   (c + 7 * S, c + 7 * S), (c, 53 * S), (c - 7 * S, c + 7 * S),
                   (11 * S, c), (c - 7 * S, c - 7 * S)], fill=stroke)
        d.ellipse([42 * S, 12 * S, 49 * S, 19 * S], fill=accent)
    elif name == "paw":
        d.ellipse([17 * S, 16 * S, 26 * S, 26 * S], fill=stroke)
        d.ellipse([29 * S, 12 * S, 38 * S, 22 * S], fill=stroke)
        d.ellipse([40 * S, 17 * S, 49 * S, 27 * S], fill=stroke)
        d.ellipse([22 * S, 29 * S, 44 * S, 49 * S], fill=stroke)
        d.ellipse([43 * S, 43 * S, 50 * S, 50 * S], fill=accent)
    elif name == "folder.open":
        d.rounded_rectangle([14 * S, 23 * S, 49 * S, 45 * S], radius=4 * S, outline=stroke, width=w)
        d.polygon([(14 * S, 29 * S), (28 * S, 18 * S), (53 * S, 18 * S), (49 * S, 45 * S)], outline=stroke)
        d.ellipse([42 * S, 12 * S, 49 * S, 19 * S], fill=accent)
    else:
        # 文件格式：统一纸张轮廓 + 类型符号 + 层级色点缀
        d.rounded_rectangle([17 * S, 14 * S, 47 * S, 50 * S], radius=4 * S, outline=stroke, width=w)
        if name == "file.markdown":
            d.line([(23 * S, 34 * S), (23 * S, 22 * S), (30 * S, 30 * S), (37 * S, 22 * S), (37 * S, 34 * S)],
                   fill=stroke, width=w, joint="curve")
        elif name == "file.code":
            d.line([(30 * S, 24 * S), (23 * S, 32 * S), (30 * S, 40 * S)], fill=stroke, width=w, joint="curve")
            d.line([(34 * S, 24 * S), (41 * S, 32 * S), (34 * S, 40 * S)], fill=stroke, width=w, joint="curve")
        elif name == "file.data":
            d.rectangle([23 * S, 24 * S, 41 * S, 40 * S], outline=stroke, width=w)
            d.line([(32 * S, 24 * S), (32 * S, 40 * S)], fill=stroke, width=w)
            d.line([(23 * S, 32 * S), (41 * S, 32 * S)], fill=stroke, width=w)
        elif name == "file.image":
            d.polygon([(23 * S, 40 * S), (30 * S, 30 * S), (36 * S, 36 * S), (40 * S, 32 * S), (41 * S, 40 * S)], fill=stroke)
            d.ellipse([34 * S, 22 * S, 40 * S, 28 * S], fill=accent)
        elif name == "file.video":
            d.polygon([(26 * S, 24 * S), (40 * S, 32 * S), (26 * S, 40 * S)], fill=stroke)
        elif name == "file.audio":
            d.line([(34 * S, 22 * S), (34 * S, 38 * S)], fill=stroke, width=w)
            d.ellipse([27 * S, 36 * S, 35 * S, 44 * S], fill=stroke)
        elif name == "file.document":
            for y in (25, 31, 37):
                d.line([(23 * S, y * S), (41 * S, y * S)], fill=stroke, width=w)
        elif name == "file.archive":
            d.rounded_rectangle([23 * S, 22 * S, 41 * S, 42 * S], radius=3 * S, outline=stroke, width=w)
            d.line([(32 * S, 22 * S), (32 * S, 42 * S)], fill=stroke, width=w)
            d.rectangle([30 * S, 28 * S, 34 * S, 33 * S], fill=accent)
        else:
            d.ellipse([28 * S, 28 * S, 36 * S, 36 * S], outline=stroke, width=w)
        d.ellipse([41 * S, 43 * S, 48 * S, 50 * S], fill=accent)
    if name in GLYPHS_ONLY:
        bbox = img.getbbox()
        if bbox:
            glyph = img.crop(bbox)
            limit = int(CANVAS * 0.8)
            ratio = min(limit / glyph.width, limit / glyph.height)
            glyph = glyph.resize((max(1, int(glyph.width * ratio)),
                                  max(1, int(glyph.height * ratio))), Image.LANCZOS)
            canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
            canvas.alpha_composite(glyph, ((CANVAS - glyph.width) // 2, (CANVAS - glyph.height) // 2))
            img = canvas
    return img.resize((64 * scale, 64 * scale), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name in ["folder", "folder.open", "file.markdown", "file.code", "file.data", "file.image",
                 "file.video", "file.audio", "file.document", "file.archive", "file.other",
                 "plugin", "settings", "sidebar", "search", "branch", "sparkle", "paw"]:
        make_icon(name, 1).save(os.path.join(out, f"{name}-64.png"))
        make_icon(name, 4).save(os.path.join(out, f"{name}-256.png"))
    print("wrote 16 files to " + os.path.abspath(out))


if __name__ == "__main__":
    main()
