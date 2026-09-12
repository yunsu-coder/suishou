#!/usr/bin/env python3
"""主题升级候选评审图：文件格式/文件夹/颜色层级/编辑字体。

用法: python3 scripts/make-theme-upgrade-review.py <review-root> <output.png>
"""

import sys
import colorsys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 1120
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"

THEMES = [
    {
        "dir": "theme-bubble-pop-v2",
        "name": "Bubble Pop · 像素糖果",
        "code_font": "fonts/FusionPixel12pxMonospacedSC.ttf",
        "ui_font": "fonts/FusionPixel12pxProportionalSC.ttf",
        "code_sample": "let note = 'bubble';",
        "panel": "#201A2E",
        "ink": "#F3E8FF",
        "accent": "#FF5FB0",
    },
    {
        "dir": "theme-sumi-paper-v2",
        "name": "墨纸 · SUMI PAPER",
        "code_font": "fonts/JetBrainsMono.ttf",
        "ui_font": "fonts/ZCOOLXiaoWei-Regular.ttf",
        "code_sample": "const ink = paper;",
        "panel": "#F6F1E7",
        "ink": "#1C1A17",
        "accent": "#C8442E",
    },
]

APP_ICONS = [("folder", "工作台"), ("plugin", "插件"), ("settings", "设置"),
             ("sidebar", "侧栏"), ("search", "搜索"), ("branch", "版本"),
             ("sparkle", "AI"), ("paw", "彩蛋")]

FILE_ICONS = [("folder.open", "文件夹"), ("file.markdown", "Markdown"),
              ("file.code", "代码"), ("file.data", "数据"), ("file.image", "图片"),
              ("file.video", "视频"), ("file.audio", "音频"), ("file.document", "文档"),
              ("file.archive", "压缩包"), ("file.other", "其他")]


def font(path, size, variation=None):
    try:
        f = ImageFont.truetype(path, size)
        if variation:
            try:
                f.set_variation_by_name(variation)
            except Exception:
                pass
        return f
    except Exception:
        return ImageFont.load_default()


def panel(d, box, fill, outline, ink):
    d.rounded_rectangle(box, radius=20, fill=fill, outline=outline, width=2)
    d.text((box[0] + 24, box[1] + 18), "", font=font(ZH, 12), fill=ink)


def signature_color(icon):
    """提取图标中的高饱和主色，用来直观展示颜色层级。"""
    rgba = icon.convert("RGBA")
    total = [0, 0, 0]
    count = 0
    fallback = [0, 0, 0]
    fallback_n = 0
    for r, g, b, a in list(rgba.getdata()):
        if a < 12:
            continue
        fallback[0] += r; fallback[1] += g; fallback[2] += b; fallback_n += 1
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.18 or v < 0.15:
            continue
        total[0] += r; total[1] += g; total[2] += b; count += 1
    if count:
        return tuple(v // count for v in total)
    if fallback_n:
        return tuple(v // fallback_n for v in fallback)
    return (128, 128, 128)


def main():
    review = Path(sys.argv[1])
    out = Path(sys.argv[2])
    img = Image.new("RGB", (W, H), "#0E1118")
    d = ImageDraw.Draw(img)
    f_title = font(ZH, 40)
    f_sub = font(ZH, 19)
    f_body = font(ZH, 16)
    f_small = font(ZH, 13)
    f_wait = font(ZH, 15)

    d.text((56, 38), "主题升级候选 · 待人工审核", font=f_title, fill="#EAF2FF")
    d.text((58, 94), "文件格式图标 / 文件夹开合 / 颜色层级 / 编辑字体 · auditVersion 2",
           font=f_sub, fill="#9FB3D9")
    d.rounded_rectangle([1250, 46, 1548, 92], radius=22, fill="#171D2B", outline="#5EE7FF", width=2)
    d.text((1274, 58), "WAITING FOR REVIEW", font=f_wait, fill="#5EE7FF")

    for idx, theme in enumerate(THEMES):
        base = review / theme["dir"]
        x = 48 + idx * 776
        y = 140
        w = 728
        panel(d, [x, y, x + w, H - 150], theme["panel"], "#FFFFFF22", theme["ink"])
        d.text((x + 24, y + 20), theme["name"], font=f_sub, fill=theme["accent"])

        # 应用图标
        d.text((x + 24, y + 58), "随手功能图标", font=f_small, fill=theme["ink"])
        for i, (key, label) in enumerate(APP_ICONS):
            ix = x + 26 + i * 82
            icon = Image.open(base / "icons" / f"{key}-64.png").convert("RGBA").resize((48, 48), Image.LANCZOS)
            img.paste(icon, (ix, y + 84), icon)
            d.text((ix + 4, y + 138), label, font=f_small, fill=theme["ink"])

        # 文件格式图标 + 颜色层级
        d.text((x + 24, y + 182), "文件格式 / 文件夹 / 颜色层级", font=f_small, fill=theme["ink"])
        for i, (key, label) in enumerate(FILE_ICONS):
            col = i % 5
            row = i // 5
            ix = x + 26 + col * 138
            iy = y + 212 + row * 96
            icon = Image.open(base / "icons" / f"{key}-64.png").convert("RGBA").resize((52, 52), Image.LANCZOS)
            img.paste(icon, (ix, iy), icon)
            d.text((ix + 2, iy + 58), label, font=f_small, fill=theme["ink"])
            chip = signature_color(icon)
            d.rounded_rectangle([ix + 2, iy + 80, ix + 22, iy + 90], radius=4, fill=chip, outline=theme["ink"], width=1)

        # 编辑字体
        code_font = font(str(base / theme["code_font"]), 22)
        ui_font = font(str(base / theme["ui_font"]), 19)
        d.text((x + 24, y + 430), "编辑面板专属字体", font=f_small, fill=theme["ink"])
        d.text((x + 24, y + 458), theme["code_sample"], font=code_font, fill=theme["accent"])
        d.text((x + 24, y + 496), "主题界面字体示例：墨纸 / Bubble Pop", font=ui_font, fill=theme["ink"])
        d.text((x + 24, y + 532), "行号标尺同步使用主题编辑字体，不再跟随用户自定义字体。",
               font=f_small, fill=theme["ink"])

    d.text((56, H - 74), "审核通过后才会替换已安装版本并重新封存 reviewedHash；未通过则继续保留当前已审核版本。",
           font=f_body, fill="#9FB3D9")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
