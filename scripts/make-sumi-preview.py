#!/usr/bin/env python3
"""SUMI PAPER 墨纸主题评审图（纯色、墨线、朱砂；无渐变，仅供审核）。

用法: python3 scripts/make-sumi-preview.py <review-dir> <output.png>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1600, 1180
LIGHT = {
    "bg": "#F6F1E7", "surface": "#FFFDF8", "panel": "#EFE7D8", "text": "#1C1A17",
    "secondary": "#6B6257", "accent": "#C8442E", "green": "#3F6B4F",
    "blue": "#3B5BA5", "code_bg": "#ECE4D6",
}
DARK = {
    "bg": "#141210", "surface": "#1E1B18", "panel": "#26221E", "text": "#F2EADF",
    "secondary": "#A99E90", "accent": "#E4573D", "green": "#7FB08C",
    "blue": "#8FA8D8", "code_bg": "#0F0D0C",
}


def font(path, size, index=0):
    try:
        return ImageFont.truetype(path, size, index=index)
    except Exception:
        return ImageFont.load_default()


def flat_panel(d, box, fill, outline, radius=16, width=2):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def swatch(d, x, y, color, name, f_name, f_hex):
    flat_panel(d, [x, y, x + 156, y + 60], color, "#1C1A17", radius=10, width=2)
    r, g, b = (int(color.lstrip("#")[i:i + 2], 16) for i in (0, 2, 4))
    lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    tc = "#1C1A17" if lum > 0.55 else "#F6F1E7"
    d.text((x + 10, y + 8), name, font=f_name, fill=tc)
    d.text((x + 10, y + 32), color, font=f_hex, fill=tc)


def window(img, d, icons, x, y, w, h, p, label, f_seal, f_ui, f_ui_sm, f_mono, f_title):
    flat_panel(d, [x, y, x + w, y + h], p["surface"], "#1C1A17", radius=18, width=2)
    d.line([(x, y + 44), (x + w, y + 44)], fill="#1C1A17", width=2)
    for i, c in enumerate(["#C8442E", "#D7A24A", "#3F6B4F"]):
        d.ellipse([x + 16 + i * 18, y + 16, x + 26 + i * 18, y + 26], fill=c)
    d.text((x + 74, y + 12), label, font=f_ui_sm, fill=p["text"])
    # 印章
    d.rounded_rectangle([x + w - 58, y + 68, x + w - 16, y + 110], radius=6, fill=p["accent"])
    d.text((x + w - 52, y + 72), "墨", font=f_seal, fill="#F6F1E7")

    # 侧栏
    d.rectangle([x + 2, y + 46, x + 190, y + h - 2], fill=p["panel"])
    d.line([(x + 190, y + 46), (x + 190, y + h - 2)], fill="#1C1A17", width=2)
    items = [("folder", "工作台"), ("plugin", "插件"), ("search", "搜索"), ("branch", "版本")]
    for i, (key, text) in enumerate(items):
        iy = y + 72 + i * 46
        if i == 0:
            d.rounded_rectangle([x + 18, iy - 6, x + 174, iy + 32], radius=8, fill=p["accent"])
        icon = Image.open(icons[key]).convert("RGBA").resize((26, 26), Image.LANCZOS)
        img.paste(icon, (x + 26, iy), icon)
        d.text((x + 62, iy + 3), text, font=f_ui_sm, fill=("#F6F1E7" if i == 0 else p["text"]))

    # 编辑器
    ex = x + 212
    ew = int(w * 0.42)
    d.text((ex, y + 70), "墨   记", font=f_seal, fill=p["text"])
    d.text((ex, y + 118), "山静似太古 / 日长如小年", font=f_ui_sm, fill=p["secondary"])
    for i in range(7):
        ly = y + 148 + i * 24
        d.text((ex, ly), f"{i + 1:>2}", font=f_mono, fill=p["secondary"])
        color = [p["text"], p["accent"], p["green"], p["blue"], p["text"], p["secondary"], p["accent"]][i]
        ww = [ew - 36, ew - 64, ew - 24, ew - 88, ew - 46, ew - 72, ew - 30][i]
        d.rounded_rectangle([ex + 28, ly + 4, ex + 28 + ww, ly + 12], radius=3, fill=color)
    d.rectangle([ex + 18, y + 148, ex + 24, y + 310], fill=p["accent"])
    d.rounded_rectangle([ex, y + 330, ex + ew, y + 430], radius=10, fill=p["code_bg"], outline="#1C1A17", width=2)
    d.text((ex + 16, y + 342), "const ink = paper;", font=f_mono, fill=p["accent"])
    d.text((ex + 16, y + 370), "render(ink);", font=f_mono, fill=p["green"])
    d.text((ex + 16, y + 398), "// whitespace", font=f_mono, fill=p["secondary"])
    # 预览
    px = ex + ew + 22
    pw = x + w - 20 - px
    d.rounded_rectangle([px, y + 66, px + pw, y + 430], radius=10, fill=p["panel"], outline="#1C1A17", width=2)
    d.text((px + 16, y + 80), "墨记", font=f_seal, fill=p["text"])
    d.line([(px + 16, y + 116), (px + pw - 20, y + 116)], fill="#1C1A17", width=2)
    for i, ww in enumerate([pw - 40, pw - 66, pw - 50]):
        d.rounded_rectangle([px + 16, y + 140 + i * 20, px + 16 + ww, y + 148 + i * 20], radius=3,
                            fill=p["secondary"])
    d.rounded_rectangle([px + 16, y + 214, px + pw - 20, y + 286], radius=8, fill=p["code_bg"])
    d.text((px + 28, y + 228), "render(ink);", font=f_mono, fill=p["green"])
    d.rounded_rectangle([px + 16, y + 310, px + 130, y + 348], radius=8, fill=p["accent"])
    d.text((px + 34, y + 320), "落笔", font=f_ui_sm, fill="#F6F1E7")
    # 状态栏
    d.line([(x + 2, y + h - 40), (x + w - 2, y + h - 40)], fill="#1C1A17", width=2)
    d.text((x + 22, y + h - 32), "Ln 12, Col 4", font=f_mono, fill=p["secondary"])
    d.text((x + w - 190, y + h - 32), "SUMI PAPER / 已同步", font=f_ui_sm, fill=p["secondary"])


def main():
    review = Path(sys.argv[1])
    out = Path(sys.argv[2])
    icons = {p.stem.replace("-64", ""): p for p in (review / "icons").glob("*-64.png")}
    f_seal = font(str(review / "fonts/MaShanZheng-Regular.ttf"), 46)
    f_seal_sm = font(str(review / "fonts/MaShanZheng-Regular.ttf"), 22)
    f_ui = font(str(review / "fonts/ZCOOLXiaoWei-Regular.ttf"), 22)
    f_ui_sm = font(str(review / "fonts/ZCOOLXiaoWei-Regular.ttf"), 17)
    f_mono = font(str(review / "fonts/JetBrainsMono.ttf"), 18)
    f_mono_sm = font(str(review / "fonts/JetBrainsMono.ttf"), 13)
    for f in (f_mono, f_mono_sm):
        try:
            f.set_variation_by_name("Regular")
        except Exception:
            pass

    img = Image.new("RGB", (W, H), LIGHT["bg"])
    d = ImageDraw.Draw(img)
    d.text((58, 40), "墨纸", font=f_seal, fill=LIGHT["text"])
    d.text((60, 104), "SUMI PAPER / 纯色墨线 / 朱砂落款 / 待人工审核", font=f_ui, fill=LIGHT["secondary"])
    flat_panel(d, [1230, 48, 1548, 98], "#F6F1E7", "#1C1A17", radius=14, width=2)
    d.text((1252, 62), "WAITING FOR REVIEW", font=f_mono_sm, fill=LIGHT["accent"])

    flat_panel(d, [48, 150, 1552, 342], LIGHT["panel"], "#1C1A17", radius=18, width=2)
    d.text((72, 168), "浅色 / 纸", font=f_ui, fill=LIGHT["secondary"])
    for i, (name, color) in enumerate([("纸底", LIGHT["bg"]), ("面板", LIGHT["surface"]), ("朱砂", LIGHT["accent"]),
                                       ("松绿", LIGHT["green"]), ("靛青", LIGHT["blue"])]):
        swatch(d, 160 + i * 176, 160, color, name, f_ui_sm, f_mono_sm)
    d.text((72, 254), "深色 / 墨", font=f_ui, fill=LIGHT["secondary"])
    for i, (name, color) in enumerate([("墨底", DARK["bg"]), ("墨面", DARK["surface"]), ("朱砂", DARK["accent"]),
                                       ("松绿", DARK["green"]), ("靛青", DARK["blue"])]):
        swatch(d, 160 + i * 176, 246, color, name, f_ui_sm, f_mono_sm)

    flat_panel(d, [48, 362, 780, 502], LIGHT["panel"], "#1C1A17", radius=18, width=2)
    d.text((72, 380), "字体 / 墨纸", font=f_ui_sm, fill=LIGHT["accent"])
    d.text((72, 406), "山静似太古", font=f_seal_sm, fill=LIGHT["text"])
    d.text((72, 444), "ZCOOL 小薇 / 正文 / 标题", font=f_ui_sm, fill=LIGHT["secondary"])
    d.text((72, 472), "const ink = paper;  // JetBrains Mono", font=f_mono, fill=LIGHT["green"])

    flat_panel(d, [804, 362, 1552, 502], LIGHT["panel"], "#1C1A17", radius=18, width=2)
    d.text((828, 380), "随手语义图标", font=f_ui_sm, fill=LIGHT["accent"])
    names = [("folder", "工作台"), ("plugin", "插件"), ("settings", "设置"), ("sidebar", "侧栏"),
             ("search", "搜索"), ("branch", "版本"), ("sparkle", "AI"), ("paw", "彩蛋")]
    for i, (key, label) in enumerate(names):
        ix = 830 + i * 88
        icon = Image.open(icons[key]).convert("RGBA").resize((50, 50), Image.LANCZOS)
        img.paste(icon, (ix, 412), icon)
        d.text((ix + 4, 470), label, font=f_ui_sm, fill=LIGHT["secondary"])

    window(img, d, icons, 48, 524, 740, 520, LIGHT, "纸 / SUMI Day", f_seal, f_ui, f_ui_sm, f_mono_sm, f_mono_sm)
    window(img, d, icons, 812, 524, 740, 520, DARK, "墨 / SUMI Night", f_seal, f_ui, f_ui_sm, f_mono_sm, f_mono_sm)

    flat_panel(d, [48, 1064, 1552, 1170], LIGHT["panel"], "#1C1A17", radius=18, width=2)
    d.text((72, 1082), "特效与彩蛋", font=f_ui_sm, fill=LIGHT["accent"])
    d.text((72, 1108), "墨迹低幅晕开 / 页签翻页弹簧 / 图标印章落下 / 不透明度呼吸（极弱）", font=f_ui_sm, fill=LIGHT["text"])
    d.text((72, 1136), "彩蛋：点击朱砂印章 -> 落款动画 + 墨点扩散；减少动态效果时自动降级。", font=f_ui_sm, fill=LIGHT["secondary"])
    for i, (title, key) in enumerate([("落笔", "sparkle"), ("翻页", "sidebar"), ("印章", "paw")]):
        fx = 930 + i * 206
        flat_panel(d, [fx, 1082, fx + 180, 1152], "#F6F1E7", "#1C1A17", radius=10, width=2)
        icon = Image.open(icons[key]).convert("RGBA").resize((38, 38), Image.LANCZOS)
        img.paste(icon, (fx + 14, 1096), icon)
        d.text((fx + 62, 1098), title, font=f_ui_sm, fill=LIGHT["text"])
        for j in range(3):
            d.ellipse([fx + 64 + j * 16, 1126, fx + 72 + j * 16, 1134],
                      fill=LIGHT["accent"] if j == i else LIGHT["secondary"])

    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
