#!/usr/bin/env python3
"""生成 4 套主题方向提案图（仅供人工选型，不安装、不进入主题列表）。

用法: python3 scripts/make-theme-proposals.py <out-dir>
"""

import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 1020
FONT_DIR = Path("plugins-market/theme-sumi-paper/fonts")
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"

CONCEPTS = [
    {
        "id": "abyss",
        "name": "深海 · ABYSS",
        "tagline": "深海蓝 + 生物荧光青，冷静、现代、专注长文",
        "fonts": ("Manrope", "JetBrains Mono"),
        "colors": {
            "bg": "#06131C", "surface": "#0C2130", "panel": "#0F2B3D",
            "text": "#E6F7FF", "secondary": "#8FB6C9", "accent": "#38E8FF",
            "accent2": "#7CFFB2", "danger": "#FF6B8A", "code_bg": "#04101A",
        },
        "icon": "line", "egg": "双击标题极光球 → 深海光晕 + 气泡雨",
        "effects": "生物荧光呼吸 · 水下光斑扫过 · 图标发光 · 页签弹簧",
    },
    {
        "id": "forge",
        "name": "熔金 · FORGE",
        "tagline": "炭黑 + 熔金橙，工业、硬朗、强调执行与力量感",
        "fonts": ("Manrope", "JetBrains Mono"),
        "colors": {
            "bg": "#14110F", "surface": "#1F1A17", "panel": "#2A211B",
            "text": "#F5EDE4", "secondary": "#B5A79A", "accent": "#FF7A3D",
            "accent2": "#FFC93C", "danger": "#E4573D", "code_bg": "#0E0C0B",
        },
        "icon": "sharp", "egg": "锤击侧栏铁砧 5 次 → 火星迸发 + 青铜铭刻",
        "effects": "余烬上浮 · 热浪微闪 · 图标锻击 · 页签金属回弹",
    },
    {
        "id": "folio",
        "name": "古籍 · FOLIO",
        "tagline": "皮革酒红 + 羊皮纸 + 黄铜，西文古典书卷气",
        "fonts": ("Ma Shan Zheng", "JetBrains Mono"),
        "colors": {
            "bg": "#1A1214", "surface": "#26191C", "panel": "#332126",
            "text": "#F4E9DC", "secondary": "#C2A79A", "accent": "#B03A48",
            "accent2": "#C89B4A", "danger": "#D14A4A", "code_bg": "#120D0F",
        },
        "icon": "serif", "egg": "点击火漆印章 → 蜡封落下 + 书页翻飞",
        "effects": "书页翻动 · 黄铜下划线扫过 · 图标盖章 · 墨色渐显",
    },
    {
        "id": "sakura",
        "name": "樱雾 · SAKURA",
        "tagline": "雾粉 + 深梅 + 藕紫，轻盈、细腻、适合日记与随笔",
        "fonts": ("ZCOOL XiaoWei", "JetBrains Mono"),
        "colors": {
            "bg": "#FFF7FA", "surface": "#FFFFFF", "panel": "#F8EDF3",
            "text": "#3A2430", "secondary": "#7A5A6C", "accent": "#D65A8E",
            "accent2": "#8E6BC8", "danger": "#C53A5A", "code_bg": "#F6EDF4",
        },
        "icon": "round", "egg": "双击花瓣印记 → 樱吹雪 + 墨色花枝",
        "effects": "花瓣飘落 · 柔光呼吸 · 图标微风 · 页签轻弹",
    },
]


def font(path, size, variation=None):
    try:
        f = ImageFont.truetype(str(path), size)
        if variation:
            try:
                f.set_variation_by_name(variation)
            except Exception:
                pass
        return f
    except Exception:
        return ImageFont.load_default()


def rgb(hex_color):
    h = hex_color.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def glyph(name, color, size=64, style="line"):
    S = 8
    img = Image.new("RGBA", (size * S, size * S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    c = size * S // 2
    w = max(2, size * S // 14)
    col = rgb(color) + (255,)

    if name == "folder":
        d.rounded_rectangle([12 * S, 22 * S, 52 * S, 48 * S], radius=5 * S, outline=col, width=w)
        d.rounded_rectangle([12 * S, 16 * S, 30 * S, 26 * S], radius=4 * S, outline=col, width=w)
    elif name == "folder.open":
        d.rounded_rectangle([12 * S, 22 * S, 52 * S, 48 * S], radius=5 * S, outline=col, width=w)
        d.polygon([(12 * S, 28 * S), (28 * S, 16 * S), (56 * S, 16 * S), (52 * S, 48 * S)], outline=col)
    elif name == "markdown":
        d.rounded_rectangle([16 * S, 12 * S, 48 * S, 52 * S], radius=4 * S, outline=col, width=w)
        d.line([(23 * S, 40 * S), (23 * S, 24 * S), (32 * S, 34 * S), (41 * S, 24 * S), (41 * S, 40 * S)],
               fill=col, width=w, joint="curve")
    elif name == "code":
        d.rounded_rectangle([16 * S, 12 * S, 48 * S, 52 * S], radius=4 * S, outline=col, width=w)
        d.line([(30 * S, 24 * S), (22 * S, 32 * S), (30 * S, 40 * S)], fill=col, width=w)
        d.line([(36 * S, 24 * S), (44 * S, 32 * S), (36 * S, 40 * S)], fill=col, width=w)
    elif name == "image":
        d.rounded_rectangle([12 * S, 16 * S, 52 * S, 48 * S], radius=5 * S, outline=col, width=w)
        d.polygon([(16 * S, 44 * S), (28 * S, 28 * S), (38 * S, 38 * S), (44 * S, 32 * S), (48 * S, 44 * S)], fill=col)
        d.ellipse([38 * S, 20 * S, 46 * S, 28 * S], fill=col)
    elif name == "video":
        d.rounded_rectangle([12 * S, 16 * S, 52 * S, 48 * S], radius=5 * S, outline=col, width=w)
        d.polygon([(27 * S, 24 * S), (42 * S, 32 * S), (27 * S, 40 * S)], fill=col)
    elif name == "audio":
        d.line([(34 * S, 16 * S), (34 * S, 40 * S)], fill=col, width=w)
        d.ellipse([24 * S, 36 * S, 36 * S, 48 * S], fill=col)
    elif name == "plugin":
        d.rounded_rectangle([24 * S, 18 * S, 42 * S, 44 * S], radius=6 * S, outline=col, width=w)
        d.line([(29 * S, 18 * S), (29 * S, 10 * S)], fill=col, width=w)
        d.line([(37 * S, 18 * S), (37 * S, 10 * S)], fill=col, width=w)
        d.line([(33 * S, 44 * S), (33 * S, 52 * S)], fill=col, width=w)
    elif name == "sparkle":
        d.polygon([(c, 10 * S), (c + 8 * S, c - 8 * S), (54 * S, c),
                   (c + 8 * S, c + 8 * S), (c, 54 * S), (c - 8 * S, c + 8 * S),
                   (10 * S, c), (c - 8 * S, c - 8 * S)], fill=col)
    elif name in ("paw", "egg"):
        d.ellipse([16 * S, 14 * S, 26 * S, 25 * S], fill=col)
        d.ellipse([29 * S, 10 * S, 39 * S, 21 * S], fill=col)
        d.ellipse([42 * S, 14 * S, 52 * S, 25 * S], fill=col)
        d.ellipse([22 * S, 28 * S, 46 * S, 52 * S], fill=col)
    if style == "sharp":
        img = img.rotate(0)
    return img.resize((size, size), Image.LANCZOS)


def draw_board(c, out):
    p = c["colors"]
    img = Image.new("RGB", (W, H), p["bg"])
    d = ImageDraw.Draw(img)
    f_title = font(FONT_DIR / "Manrope-Bold.ttf", 42)
    f_zh = font(ZH, 19)
    f_body = font(ZH, 15)
    f_small = font(ZH, 13)
    mono = font(FONT_DIR / "JetBrainsMono.ttf", 18, "Regular")

    d.text((52, 34), c["name"], font=f_title, fill=p["accent"])
    d.text((54, 92), c["tagline"], font=f_zh, fill=p["text"])
    d.rounded_rectangle([1260, 44, 1548, 88], radius=20, fill=p["panel"], outline=p["accent"], width=2)
    d.text((1282, 56), "CONCEPT PROPOSAL", font=font(FONT_DIR / "Manrope-Bold.ttf", 14), fill=p["accent2"])

    # 配色
    d.rounded_rectangle([40, 132, 760, 300], radius=18, fill=p["surface"], outline=p["accent"] + "66", width=2)
    d.text((64, 150), "配色", font=f_zh, fill=p["text"])
    for i, (name, key) in enumerate([("背景", "bg"), ("面板", "surface"), ("主色", "accent"),
                                     ("辅色", "accent2"), ("正文", "text"), ("次级", "secondary")]):
        x = 64 + i * 112
        d.rounded_rectangle([x, 184, x + 96, 244], radius=10, fill=p[key], outline=p["accent"] + "55", width=1)
        r, g, b = rgb(p[key])
        lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
        tc = "#111111" if lum > 0.6 else "#FFFFFF"
        d.text((x + 8, 192), name, font=f_small, fill=tc)
        d.text((x + 8, 216), p[key], font=font(FONT_DIR / "JetBrainsMono.ttf", 11, "Regular"), fill=tc)

    # 字体
    d.rounded_rectangle([800, 132, 1560, 300], radius=18, fill=p["surface"], outline=p["accent"] + "66", width=2)
    d.text((824, 150), "字体", font=f_zh, fill=p["text"])
    d.text((824, 182), "Aurora Notes 2026", font=font(FONT_DIR / "Manrope-Bold.ttf", 26), fill=p["text"])
    d.text((824, 222), "const theme = 'aurora';", font=mono, fill=p["accent"])
    d.text((824, 252), " · ".join(c["fonts"]), font=f_small, fill=p["secondary"])

    # 图标
    d.rounded_rectangle([40, 320, 1560, 500], radius=18, fill=p["surface"], outline=p["accent"] + "66", width=2)
    d.text((64, 338), "图标语义（应用 + 文件格式层级）", font=f_zh, fill=p["text"])
    icons = [("folder", "工作台"), ("plugin", "插件"), ("sparkle", "AI"), ("egg", "彩蛋"),
             ("folder.open", "文件夹"), ("markdown", "Markdown"), ("code", "代码"), ("image", "图片"),
             ("video", "视频"), ("audio", "音频")]
    for i, (key, label) in enumerate(icons):
        x = 68 + i * 148
        icon = glyph(key, p["accent"] if i % 3 == 0 else (p["accent2"] if i % 3 == 1 else p["secondary"]), 54)
        img.paste(icon, (x, 374), icon)
        d.text((x + 2, 440), label, font=f_small, fill=p["secondary"])

    # 窗口示意
    d.rounded_rectangle([40, 520, 1560, 860], radius=18, fill=p["surface"], outline=p["accent"] + "66", width=2)
    d.rounded_rectangle([64, 548, 300, 832], radius=14, fill=p["panel"])
    d.text((84, 566), "资源管理器", font=f_body, fill=p["text"])
    for i, label in enumerate(["工作台", "插件", "搜索", "版本"]):
        y = 606 + i * 40
        if i == 0:
            d.rounded_rectangle([76, y - 6, 288, y + 28], radius=8, fill=p["accent"] + "33")
        d.text((92, y), label, font=f_body, fill=p["text"] if i == 0 else p["secondary"])
    d.text((336, 562), "AURORA NOTES", font=font(FONT_DIR / "Manrope-Bold.ttf", 16), fill=p["accent2"])
    for i, ww in enumerate([520, 470, 540, 420]):
        d.rounded_rectangle([336, 596 + i * 22, 336 + ww, 606 + i * 22], radius=4, fill=p["text"] + "55")
    d.rounded_rectangle([336, 700, 820, 812], radius=12, fill=p["code_bg"])
    d.text((354, 714), "const theme = 'new';", font=mono, fill=p["accent"])
    d.text((354, 744), "await launch(theme);", font=mono, fill=p["accent2"])
    d.rounded_rectangle([860, 548, 1536, 832], radius=14, fill=p["panel"])
    d.text((884, 566), "预览", font=f_zh, fill=p["text"])
    for i, ww in enumerate([560, 500, 540]):
        d.rounded_rectangle([884, 604 + i * 24, 884 + ww, 614 + i * 24], radius=4, fill=p["secondary"] + "88")
    d.rounded_rectangle([884, 696, 1300, 780], radius=10, fill=p["code_bg"])
    d.text((902, 712), "render(theme);", font=mono, fill=p["accent2"])
    d.rounded_rectangle([884, 796, 1020, 824], radius=10, fill=p["accent"])

    # 动效 & 彩蛋
    d.rounded_rectangle([40, 880, 1560, 986], radius=18, fill=p["panel"], outline=p["accent"] + "66", width=2)
    d.text((64, 898), "专属特效 / 动画", font=f_zh, fill=p["text"])
    d.text((64, 926), c["effects"], font=f_body, fill=p["secondary"])
    d.text((64, 954), "专属彩蛋：" + c["egg"], font=f_body, fill=p["accent2"])
    img.save(out)
    return img


def main():
    out_dir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/theme-proposals")
    out_dir.mkdir(parents=True, exist_ok=True)
    thumbs = []
    for c in CONCEPTS:
        path = out_dir / f"proposal-{c['id']}.png"
        img = draw_board(c, path)
        thumbs.append((c, img))
        print(path)

    sheet = Image.new("RGB", (W, H + 240), "#0B0F16")
    sd = ImageDraw.Draw(sheet)
    sd.text((52, 30), "新主题方向提案 · 四选一或混合", font=font(ZH, 36), fill="#EAF2FF")
    sd.text((54, 82), "全部非像素；每套包含专属字体、语义图标、颜色层级、动效与彩蛋", font=font(ZH, 17), fill="#9FB3D9")
    for i, (c, img) in enumerate(thumbs):
        x = 20 + (i % 2) * 790
        y = 130 + (i // 2) * 540
        thumb = img.resize((770, 490), Image.LANCZOS)
        sheet.paste(thumb, (x, y))
        sd.text((x + 12, y + 496), c["name"], font=font(ZH, 15), fill="#EAF2FF")
    sheet.save(out_dir / "proposals-overview.png")
    print(out_dir / "proposals-overview.png")


if __name__ == "__main__":
    main()
