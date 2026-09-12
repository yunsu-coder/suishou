#!/usr/bin/env python3
"""体验型主题提案：展示随交互变化的叙事与情绪，而不是静态皮肤。

用法: python3 scripts/make-experience-proposals.py <out.png>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1220
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False):
    try:
        return ImageFont.truetype(ZH, size, index=1 if bold else 0)
    except Exception:
        return ImageFont.load_default()


def label(d, xy, text, size=15, color="#EAF2FF", bold=False):
    d.text(xy, text, font=font(size, bold), fill=color)


def luminance(hex_color):
    h = hex_color.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) for i in (0, 2, 4))
    return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255


def frame(d, x, y, w, h, fill, outline, title, caption):
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill=fill, outline=outline, width=2)
    label(d, (x + 14, y + 10), title, 15, outline, True)
    cap = "#1B1F3B" if luminance(fill) > 0.62 else "#DCE6FF"
    label(d, (x + 14, y + h - 28), caption, 13, cap)


def companion(d, x, y):
    label(d, (x, y), "旅伴 · 灯下小兽", 26, "#FFC98B", True)
    label(d, (x, y + 34), "情绪钩子：写作不再是独处；它会醒、会累、会因为你的进度成长。", 15, "#C9B8A6")
    frames = [
        ("打开", "小兽在台灯下睡着，界面是温暖书桌"),
        ("输入", "它醒来跟着光标移动，灯光随打字呼吸"),
        ("保存", "它盖章拍爪，纸页获得一枚小印记"),
        ("闲置", "它打盹，页面变暗，只留呼吸光"),
    ]
    for i, (t, c) in enumerate(frames):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 200, "#241B17", "#FFC98B", t, c)
        # 小兽
        cx, cy = fx + 200, y + 170
        if t == "闲置":
            d.ellipse([cx - 55, cy - 20, cx + 55, cy + 40], fill="#8A5C3B")
            d.ellipse([cx - 30, cy - 8, cx - 18, cy + 4], fill="#241B17")
            d.ellipse([cx + 18, cy - 8, cx + 30, cy + 4], fill="#241B17")
        else:
            d.ellipse([cx - 45, cy - 35, cx + 45, cy + 40], fill="#C98A57")
            d.polygon([(cx - 40, cy - 28), (cx - 20, cy - 62), (cx - 6, cy - 26)], fill="#C98A57")
            d.polygon([(cx + 40, cy - 28), (cx + 20, cy - 62), (cx + 6, cy - 26)], fill="#C98A57")
            d.ellipse([cx - 22, cy - 12, cx - 12, cy - 2], fill="#241B17")
            d.ellipse([cx + 12, cy - 12, cx + 22, cy - 2], fill="#241B17")
            if t == "保存":
                d.ellipse([cx + 30, cy + 10, cx + 50, cy + 30], outline="#FFC98B", width=3)


def seasons(d, x, y):
    label(d, (x, y), "四季 · 窗外", 26, "#8CFFC1", True)
    label(d, (x, y + 34), "情绪钩子：界面会随真实日期、时间与写作积累而变化，不是静态主题。", 15, "#A9C4B4")
    frames = [
        ("春", "樱花飘落，新叶与浅粉纸面"),
        ("夏", "绿荫与蝉鸣光斑，薄荷强调色"),
        ("秋", "枫叶与暖金，纸张偏黄"),
        ("冬", "雪窗与冷蓝，氤氲呼吸光"),
    ]
    colors = [("#FFD7E6", "#D65A8E"), ("#CDEFD9", "#2F7F5F"),
              ("#FFE3B8", "#C45A1E"), ("#DBE9FF", "#3B6FB5")]
    for i, (t, c) in enumerate(frames):
        fx = x + i * 430
        bg, ac = colors[i]
        frame(d, fx, y + 70, 400, 200, bg, ac, t, c)
        for j in range(6):
            dx = fx + 40 + j * 58
            dy = y + 110 + (j % 3) * 24
            if i == 0:
                d.ellipse([dx, dy, dx + 16, dy + 10], fill="#D65A8E88")
            elif i == 1:
                d.ellipse([dx, dy, dx + 14, dy + 14], fill="#2F7F5F66")
            elif i == 2:
                d.polygon([(dx, dy + 10), (dx + 8, dy), (dx + 16, dy + 10)], fill="#C45A1E88")
            else:
                d.ellipse([dx, dy, dx + 6, dy + 6], fill="#3B6FB599")


def typewriter(d, x, y):
    label(d, (x, y), "旧信 · 打字机", 26, "#F0B27A", True)
    label(d, (x, y + 34), "情绪钩子：写作变成一种仪式；每个动作有机械反馈与纸面落款。", 15, "#D2BBA6")
    frames = [
        ("入纸", "纸张卷入压纸卷轴，带动轻微弹动"),
        ("敲键", "按键落下，墨带色随主题变化"),
        ("保存", "蜡封落章，角落出现邮戳"),
        ("归档", "信件叠成抽屉，版本成为副本"),
    ]
    for i, (t, c) in enumerate(frames):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 200, "#1E1A18", "#F0B27A", t, c)
        if i == 0:
            d.rounded_rectangle([fx + 110, y + 100, fx + 300, y + 210], radius=6, fill="#F5EDE4", outline="#8A6A4A", width=2)
            for k in range(6):
                d.line([(fx + 130, y + 120 + k * 14), (fx + 280, y + 120 + k * 14)], fill="#B8A58F", width=2)
        elif i == 1:
            for r in range(3):
                for cidx in range(6):
                    kx, ky = fx + 90 + cidx * 36, y + 130 + r * 32
                    d.rounded_rectangle([kx, ky, kx + 28, ky + 24], radius=5, fill="#2E2723", outline="#F0B27A", width=1)
        elif i == 2:
            d.rounded_rectangle([fx + 120, y + 110, fx + 290, y + 200], radius=8, fill="#F5EDE4", outline="#8A6A4A", width=2)
            d.ellipse([fx + 240, y + 160, fx + 284, y + 204], outline="#B03A48", width=6)
        else:
            d.rounded_rectangle([fx + 100, y + 120, fx + 310, y + 200], radius=8, fill="#2E2723", outline="#F0B27A", width=2)
            d.line([(fx + 120, y + 150), (fx + 290, y + 150)], fill="#F0B27A", width=3)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/experience-themes.png")
    img = Image.new("RGB", (W, H), "#0C1016")
    d = ImageDraw.Draw(img)
    label(d, (48, 34), "体验型主题提案 · 不是皮肤，是会变化的陪伴", 38, "#EAF2FF", True)
    label(d, (50, 88), "每一行展示同一主题在 打开 → 输入 → 保存 → 闲置/归档 四个阶段的行为与情绪反馈", 18, "#9FB3D9")
    companion(d, 48, 140)
    seasons(d, 48, 480)
    typewriter(d, 48, 820)
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
