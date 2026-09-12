#!/usr/bin/env python3
"""生成随手 Bubble Pop 主题的语义图标（16/64px，透明背景）。

用法: python3 scripts/make-bubble-pop-icons.py <输出目录>
"""

import os
import sys

from PIL import Image, ImageDraw

OUTLINE = "#4A2B63"

# 8x8 点阵：X 为符号像素。图标语义与随手功能一一对应。
SYMBOLS = {
    # 工作台 / 文件夹
    "folder":   ["XXX.....", "XXXXXXX.", "XXXXXXX.", "XXXXXXX.", "XXXXXXX.", "XXXXXXX.", ".XXXXX..", "........"],
    "folder.open": ["XXX.....", "XXXXXXX.", "XXXXXXX.", "XXXXXXX.", "X.....X.", "X.....X.", "XXXXXXXX", "........"],
    # 文件格式图标（颜色层级区分）
    "file.markdown": ["X.....X.", "XX...XX.", "X.X.X.X.", "X..X..X.", "X.....X.", "X.....X.", "........", "........"],
    "file.code":     ["..X..X..", ".X....X.", "X......X", ".X....X.", "..X..X..", "........", "........", "........"],
    "file.data":     ["XXXXXXX.", "X.X.X.X.", "XXXXXXX.", "X.X.X.X.", "XXXXXXX.", "........", "........", "........"],
    "file.image":    ["....X...", "..XXXX..", "XXXXXXX.", "X.XXXXX.", "XXXXXXX.", "........", "........", "........"],
    "file.video":    ["X.......", "XX......", "XXX.....", "XXXX....", "XXX.....", "XX......", "X.......", "........"],
    "file.audio":    ["..XXX...", "..X.....", "..X.....", "..X.....", "XXX.....", "XXX.....", "........", "........"],
    "file.document": ["XXXXXXX.", "X.....X.", "XXXXXXX.", "X.....X.", "XXXXXXX.", "........", "........", "........"],
    "file.archive":  ["XXXXXXX.", "X..X..X.", "XXXXXXX.", "X..X..X.", "XXXXXXX.", "........", "........", "........"],
    "file.other":    ["...X....", "..XXX...", ".XXXXX..", "..XXX...", "...X....", "........", "........", "........"],
    # 插件市场 / 扩展插头
    "plugin":   ["..XX....", ".X..X...", "XXXXXX..", "XX..XX..", "XX..XX..", "XXXXXX..", ".X..X...", "..XX...."],
    # 设置 / 齿轮
    "settings": ["..X..X..", ".XXXXXX.", "XXX..XXX", "XX....XX", "XX....XX", "XXX..XXX", ".XXXXXX.", "..X..X.."],
    # 侧栏显隐
    "sidebar":  ["XXXXXXX.", "X.....X.", "X..X..X.", "X.....X.", "X..X..X.", "X.....X.", "XXXXXXX.", "........"],
    # 搜索
    "search":   [".XXX....", "X...X...", "X...X...", "X...X...", ".XXX....", "...XX...", "....XX..", "........"],
    # 版本历史（分支）
    "branch":   ["..X...X.", "..X...X.", "..X...X.", "...X.X..", "....X...", "...X.X..", "..X...X.", "........"],
    # AI / 智能
    "sparkle":  ["...X....", "..XXX...", ".XXXXX..", "XXXXXXX.", ".XXXXX..", "..XXX...", "...X....", "........"],
    # 彩蛋 / 宠物
    "paw":      [".X.X.X..", ".X.X.X..", "..XXX...", ".XXXXX..", ".XXXXX..", "..XXX...", "........", "........"],
}

ICON_COLORS = {
    "folder":   ("#FFC93C", "#FFE9A8", "#C99A10"),
    "folder.open": ("#FFD966", "#FFF3C4", "#D1A21A"),
    "file.markdown": ("#7FA4D8", "#D6E4FF", "#4F6FA8"),
    "file.code":     ("#9A6BFF", "#D9C7FF", "#6B3FD6"),
    "file.data":     ("#4FD1A5", "#C4F7E5", "#2A9C78"),
    "file.image":    ("#43C6D8", "#BEEFF7", "#238FA0"),
    "file.video":    ("#FF8A5C", "#FFD2BD", "#C95327"),
    "file.audio":    ("#FF7AB6", "#FFCBE2", "#C43D7E"),
    "file.document": ("#8C9BB5", "#D8E0EE", "#5B6B86"),
    "file.archive":  ("#D9A05B", "#F4DDBD", "#A66F2E"),
    "file.other":    ("#9AA0AC", "#DEE1E7", "#6B7280"),
    "plugin":   ("#7C4DFF", "#C0ACFF", "#5B31D6"),
    "settings": ("#4FB8FF", "#B0E1FF", "#2F86C7"),
    "sidebar":  ("#3ECFA0", "#A6F2D8", "#1F9C74"),
    "search":   ("#4FB8FF", "#B0E1FF", "#2F86C7"),
    "branch":   ("#FFC93C", "#FFE9A8", "#C99A10"),
    "sparkle":  ("#C77DFF", "#E8CBFF", "#9A4FD6"),
    "paw":      ("#FF8FB1", "#FFCCDD", "#D96A8C"),
}

# 文件类型与文件夹图标：透明字形、无底板、小尺寸使用。
GLYPHS_ONLY = {
    "folder", "folder.open",
    "file.markdown", "file.code", "file.data", "file.image",
    "file.video", "file.audio", "file.document", "file.archive", "file.other",
}


def hx(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (255,)


def rgba(color, alpha):
    r, g, b, _ = hx(color)
    return (r, g, b, alpha)


def mix(a, b, t):
    ca, cb = hx(a), hx(b)
    return tuple(round(ca[i] + (cb[i] - ca[i]) * t) for i in range(3)) + (255,)


def make_icon(name, scale=1):
    base, light, dark = ICON_COLORS[name]
    size = 16
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    if name in GLYPHS_ONLY:
        for y, row in enumerate(SYMBOLS[name]):
            for x, ch in enumerate(row):
                if ch == "X":
                    draw = ImageDraw.Draw(img)
                    draw.rectangle([x * 2, min(15, y * 2 + 1), x * 2 + 1, min(15, y * 2 + 2)],
                                   fill=hx(OUTLINE))
        for y, row in enumerate(SYMBOLS[name]):
            for x, ch in enumerate(row):
                if ch == "X":
                    ImageDraw.Draw(img).rectangle([x * 2, y * 2, x * 2 + 1, y * 2 + 1], fill=hx(base))
        return img.resize((size * scale, size * scale), Image.NEAREST) if scale > 1 else img
    draw = ImageDraw.Draw(img)
    draw.rounded_rectangle([0, 0, 15, 15], radius=5, fill=hx(OUTLINE))

    grad = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    grad_draw = ImageDraw.Draw(grad)
    for y in range(1, 15):
        t = (y - 1) / 13
        color = mix(base, light, max(0.0, 1 - t / 0.5)) if t < 0.5 else mix(base, dark, (t - 0.5) / 0.5 * 0.9)
        grad_draw.line([(1, y), (14, y)], fill=color)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle([1, 1, 14, 14], radius=4, fill=255)
    img.paste(grad, (0, 0), mask)

    draw.line([(4, 2), (11, 2)], fill=rgba("#FFFFFF", 120))
    draw.line([(3, 3), (4, 3)], fill=rgba("#FFFFFF", 90))
    draw.line([(4, 13), (11, 13)], fill=rgba(OUTLINE, 60))

    for y, row in enumerate(SYMBOLS[name]):
        for x, ch in enumerate(row):
            if ch == "X":
                img.putpixel((x + 4, y + 5), hx(OUTLINE))
    for y, row in enumerate(SYMBOLS[name]):
        for x, ch in enumerate(row):
            if ch == "X":
                img.putpixel((x + 4, y + 4), hx("#FFFFFF"))

    if scale > 1:
        img = img.resize((size * scale, size * scale), Image.NEAREST)
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)
    for name in SYMBOLS:
        make_icon(name, 1).save(os.path.join(out_dir, f"{name}-16.png"))
        make_icon(name, 4).save(os.path.join(out_dir, f"{name}-64.png"))
    print(f"wrote {len(SYMBOLS) * 2} files to {os.path.abspath(out_dir)}")


if __name__ == "__main__":
    main()
