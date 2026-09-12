#!/usr/bin/env python3
"""v3 文件/文件夹图标评审图：对比“有底板 v2”和“透明字形 v3”。

用法: python3 scripts/make-theme-v3-review.py <plugins-market> <output.png>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 980
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
KEYS = [("folder", "文件夹"), ("folder.open", "展开"), ("file.markdown", "Markdown"),
        ("file.code", "代码"), ("file.data", "数据"), ("file.image", "图片"),
        ("file.video", "视频"), ("file.audio", "音频"), ("file.document", "文档"),
        ("file.archive", "压缩包"), ("file.other", "其他")]


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except Exception:
        return ImageFont.load_default()


def draw_icon_row(img, d, icons_dir, y, f_label, nearest=False):
    for i, (key, label) in enumerate(KEYS):
        x = 60 + i * 136
        icon = Image.open(icons_dir / f"{key}-64.png").convert("RGBA")
        # 64px 预览
        big = icon.resize((52, 52), Image.NEAREST if nearest else Image.LANCZOS)
        img.paste(big, (x, y), big)
        # 14px 文件树真实尺寸
        small = icon.resize((14, 14), Image.NEAREST if nearest else Image.LANCZOS)
        img.paste(small, (x + 19, y + 62), small)
        d.text((x + 2, y + 84), label, font=f_label, fill="#DCE6FF")


def main():
    market = Path(sys.argv[1])
    out = Path(sys.argv[2])
    img = Image.new("RGB", (W, H), "#0E1118")
    d = ImageDraw.Draw(img)
    f_title = font(ZH, 38)
    f_sub = font(ZH, 18)
    f_body = font(ZH, 15)
    f_small = font(ZH, 13)

    d.text((56, 36), "文件 / 文件夹图标升级 · v3 候选 · 待人工审核", font=f_title, fill="#EAF2FF")
    d.text((58, 90), "规则：透明字形、无背景底板、不透明覆盖率 ≤80%、14px 文件树可辨",
           font=f_sub, fill="#9FB3D9")
    d.rounded_rectangle([1250, 44, 1548, 88], radius=20, fill="#171D2B", outline="#5EE7FF", width=2)
    d.text((1270, 56), "WAITING FOR REVIEW", font=f_small, fill="#5EE7FF")

    themes = [
        ("Bubble Pop", market / "theme-bubble-pop" / "icons",
         market / "_review" / "theme-bubble-pop-v3" / "icons", True),
        ("墨纸 · SUMI PAPER", market / "theme-sumi-paper" / "icons",
         market / "_review" / "theme-sumi-paper-v3" / "icons", False),
    ]

    y = 140
    for name, v2icons, v3icons, nearest in themes:
        d.rounded_rectangle([40, y, W - 40, y + 380], radius=20, fill="#161C29", outline="#FFFFFF22", width=1)
        d.text((64, y + 18), name, font=f_sub, fill="#5EE7FF")
        d.text((64, y + 52), "当前 v2：有底板，14px 下偏重", font=f_small, fill="#FFB4B4")
        draw_icon_row(img, d, v2icons, y + 78, f_small, nearest)
        d.text((64, y + 196), "v3 候选：透明字形，无底板，小尺寸更轻", font=f_small, fill="#8CFFC1")
        draw_icon_row(img, d, v3icons, y + 222, f_small, nearest)
        y += 400

    d.text((56, H - 52), "通过审核后才会替换正式包并重新封存 reviewedHash；当前已审核版本继续生效。",
           font=f_body, fill="#9FB3D9")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
