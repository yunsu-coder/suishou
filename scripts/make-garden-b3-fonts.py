#!/usr/bin/env python3
"""B3 雾青 · 字体配对样张（亮色主题）。真实字体渲染，不用占位名。

用法: python3 scripts/make-garden-b3-fonts.py <out.png>
"""

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("gt", HERE / "make-game-themes.py")
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)
T = gt.T

SONG = gt.SONG
HIRA = gt.HIRA
MONO = "/Users/gzhysu/Desktop/note/plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf"
XIAOWEI = "/Users/gzhysu/Desktop/note/plugins-market/theme-sumi-paper/fonts/ZCOOLXiaoWei-Regular.ttf"
KAI = "/Users/gzhysu/Desktop/note/plugins-market/theme-sumi-paper/fonts/MaShanZheng-Regular.ttf"

C = gt.PALETTES["garden"]
BG = "#0B0E14"


def F(p, s, i=0):
    return gt.F(p, s, i)


PAIRINGS = [
    dict(id="P1", name="清朗（推荐）", mood="标题秀丽、正文中性，14px 长文最稳",
         title_font=(XIAOWEI, 32, 0), body_font=(HIRA, 15, 0), small_font=(HIRA, 13, 0),
         code_font=(MONO, 13, 0),
         fonts=[("标题", "站酷小薇 ZCOOL XiaoWei", "开源 OFL · 6.3 MB（随主题自带）"),
                ("正文 / 界面", "苹方 Hiragino Sans GB W3", "macOS 系统字体 · 0 MB"),
                ("代码 / 行号", "JetBrains Mono", "开源 OFL · 187 KB（随主题自带）")]),
    dict(id="P2", name="书卷", mood="全宋体，最像纸质书；小字号偏细，需 15px 起",
         title_font=(SONG, 32, 0), body_font=(SONG, 15, 3), small_font=(HIRA, 13, 0),
         code_font=(MONO, 13, 0),
         fonts=[("标题", "宋体 Songti SC Black", "macOS 系统字体 · 0 MB"),
                ("正文 / 界面", "宋体 Songti SC Light", "macOS 系统字体 · 0 MB"),
                ("代码 / 行号", "JetBrains Mono", "开源 OFL · 187 KB（随主题自带）")]),
    dict(id="P3", name="手记", mood="楷书标题 + 黑体正文，最有手写温度",
         title_font=(KAI, 34, 0), body_font=(HIRA, 15, 0), small_font=(HIRA, 13, 0),
         code_font=(MONO, 13, 0),
         fonts=[("标题", "马善政楷书 Ma Shan Zheng", "开源 OFL · 5.9 MB（随主题自带）"),
                ("正文 / 界面", "苹方 Hiragino Sans GB W3", "macOS 系统字体 · 0 MB"),
                ("代码 / 行号", "JetBrains Mono", "开源 OFL · 187 KB（随主题自带）")]),
]


def panel(img, d, x, y, w, h, pairing, colors, recommended=False):
    p = pairing
    d.rounded_rectangle([x, y, x + w, y + h], radius=16, fill="#111722",
                        outline=colors["accent"] if recommended else "#1F2937",
                        width=2 if recommended else 1)
    d.rounded_rectangle([x + 24, y + 22, x + 24 + 6, y + 62], radius=3, fill=colors["accent"])
    T(d, x + 44, y + 20, f"{p['id']} · {p['name']}", F(HIRA, 20, 2), "#EFF4FF")
    T(d, x + 44, y + 54, p["mood"], F(HIRA, 13), "#8FA0BB")

    fy = y + 96
    for role, name, source in p["fonts"]:
        T(d, x + 44, fy, role, F(HIRA, 12, 2), colors["accent"])
        T(d, x + 152, fy, name, F(HIRA, 13), "#D7E1F0")
        T(d, x + 152, fy + 22, source, F(HIRA, 11), "#6F7E96")
        fy += 54

    # 标题 + 正文样张
    ts, bs, ss, cs = p["title_font"], p["body_font"], p["small_font"], p["code_font"]
    bx = x + 640
    d.rounded_rectangle([bx - 30, y + 22, x + w - 24, y + h - 22], radius=12, fill=colors["bg"],
                        outline=colors["line"])
    T(d, bx, y + 46, "秋分　阳台观察记", F(*ts), colors["text"])
    d.line([(bx, y + 100), (x + w - 54, y + 100)], fill=colors["line"])
    T(d, bx, y + 116, "今天风很大，我把薄荷搬到了窗边。记录第七朵花开了，", F(*bs), colors["text"])
    T(d, bx, y + 144, "顺手写下浇水与日照时数，明天再来看它。", F(*bs), colors["text"])
    T(d, bx, y + 186, "小字号正文 13px：写下 800 字它会开花，闲置 7 天会休眠。", F(*ss), colors["dim"])
    T(d, bx, y + 220, "链接 花期记录", F(*bs), colors["accent"])
    d.rounded_rectangle([bx + 150, y + 214, bx + 300, y + 250], radius=8, fill=colors["card2"])
    gt.T_mix(d, bx + 162, y + 216, "字数 +800", F(*cs), F(HIRA, 13), colors["text"])

    # 数字与代码
    cx = x + w - 470
    d.rounded_rectangle([cx, y + 116, x + w - 24, y + h - 22], radius=12, fill=colors["card"],
                        outline=colors["line"])
    T(d, cx + 20, y + 132, "数值 / 状态栏", F(HIRA, 12, 2), colors["accent"])
    gt.T_mix(d, cx + 20, y + 152, "1,240 字 · 12 天 · Lv.12", F(*cs), F(HIRA, 13), colors["text"])
    gt.T_mix(d, cx + 20, y + 180, "09-11 · 128 / 200 字", F(*cs), F(HIRA, 13), colors["dim"])
    d.line([(cx + 20, y + 214), (x + w - 44, y + 214)], fill=colors["line"])
    T(d, cx + 20, y + 226, "def grow(words):", F(*cs), colors["accent"])
    gt.T_mix(d, cx + 20, y + 244, "    return words * 0.1  # 每 10 字一厘米", F(*cs), F(HIRA, 13),
             colors["dim"])


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/game/garden-b3-fonts.png")
    W, H = 1840, 1180
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    T(d, 48, 34, "B3 雾青 · 字体配对样张（亮色）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "真实字体渲染。规则：字体家族由主题决定，字号仍由你的滑杆控制；单字体体积上限 12 MB。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 300, 46, W - 48, 90], radius=20, fill="#161C26", outline=C["accent"])
    T(d, W - 174, 68, "待人工审核 · 未安装", F(HIRA, 13), C["accent"], anchor="mm")

    for i, p in enumerate(PAIRINGS):
        panel(img, d, 48, 134 + i * 336, W - 96, 312, p, C, recommended=(i == 0))

    T(d, 48, H - 46, "若希望正文也不依赖系统字体：可以把「霞鹜文楷」或「思源宋体」打进主题包（约 5–8 MB，仍在门槛内）。",
      F(HIRA, 13), "#6F7E96")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
