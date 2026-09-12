#!/usr/bin/env python3
"""游戏化主题方向提案：写作进度驱动可见的游戏系统。

用法: python3 scripts/make-gamified-proposals.py <out.png>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1280
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False):
    try:
        return ImageFont.truetype(ZH, size, index=1 if bold else 0)
    except Exception:
        return ImageFont.load_default()


def label(d, xy, text, size=15, color="#EAF2FF", bold=False):
    d.text(xy, text, font=font(size, bold), fill=color)


def frame(d, x, y, w, h, fill, outline, title, caption):
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill=fill, outline=outline, width=2)
    label(d, (x + 14, y + 10), title, 15, outline, True)
    label(d, (x + 14, y + h - 30), caption, 13, "#DCE6FF")


def quest_log(d, x, y):
    label(d, (x, y), "冒险者公会 · QUEST LOG", 26, "#FFC98B", True)
    label(d, (x, y + 34), "核心循环：写作 = 完成任务 → 获得经验 → 解锁称号 / 区域 / 剧情。", 15, "#C9B8A6")
    steps = [
        ("接任务", "每篇文档是一张任务卡"),
        ("积累经验", "字数 / 保存 / 连更 → XP"),
        ("升级解锁", "等级、称号、头像框、地图区域"),
        ("成就与 Boss", "长文完结 = 击败 Boss，掉落成就"),
    ]
    for i, (t, c) in enumerate(steps):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 210, "#241B17", "#FFC98B", t, c)
        if i == 0:
            d.rounded_rectangle([fx + 60, y + 110, fx + 340, y + 200], radius=8, fill="#F5EDE4", outline="#8A6A4A", width=2)
            label(d, (fx + 84, y + 126), "Quest: 今晚写完 800 字", 14, "#2B211A")
        elif i == 1:
            d.rounded_rectangle([fx + 60, y + 170, fx + 340, y + 194], radius=10, fill="#3A2C24")
            d.rounded_rectangle([fx + 60, y + 170, fx + 250, y + 194], radius=10, fill="#FFC98B")
            label(d, (fx + 72, y + 118), "XP 1240 / 2000", 15, "#FFC98B", True)
        elif i == 2:
            d.ellipse([fx + 150, y + 110, fx + 250, y + 210], outline="#FFC98B", width=6)
            label(d, (fx + 176, y + 146), "Lv.12", 18, "#FFC98B", True)
        else:
            d.rounded_rectangle([fx + 70, y + 110, fx + 330, y + 200], radius=10, fill="#3A2C24", outline="#FFC98B", width=2)
            label(d, (fx + 100, y + 130), "“长夜执笔者”", 17, "#FFC98B", True)


def write_city(d, x, y):
    label(d, (x, y), "写字城 · WRITE CITY", 26, "#8CC8FF", True)
    label(d, (x, y + 34), "核心循环：写作产出资源 → 建楼 → 扩张城区 → 城市昼夜与节日变化。", 15, "#A9C4E6")
    steps = [
        ("产出资源", "字数 = 木石；保存 = 金币"),
        ("建造", "每篇文档生成一栋建筑"),
        ("扩张", "文件夹 = 城区；连更 = 人口"),
        ("城市庆典", "里程碑解锁夜景与烟花"),
    ]
    for i, (t, c) in enumerate(steps):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 210, "#101C2E", "#8CC8FF", t, c)
        base_y = y + 210
        for j in range(i + 1):
            bw = 54
            bx = fx + 80 + j * 70
            bh = 40 + (j % 3) * 26
            d.rectangle([bx, base_y - bh, bx + bw, base_y], fill="#8CC8FF" if j == i else "#35587F")
            for wy in range(base_y - bh + 10, base_y - 6, 16):
                d.rectangle([bx + 10, wy, bx + 20, wy + 7], fill="#F5EDE4")
                d.rectangle([bx + 34, wy, bx + 44, wy + 7], fill="#F5EDE4")
        if i == 3:
            d.ellipse([fx + 300, y + 100, fx + 320, y + 120], fill="#FFC98B")


def cultivation(d, x, y):
    label(d, (x, y), "墨境修行 · CULTIVATION", 26, "#8CFFC1", True)
    label(d, (x, y + 34), "核心循环：写作 = 修行 → 灵气与经脉增长 → 破境 → 解锁功法与洞府。", 15, "#A9C4B4")
    steps = [
        ("入定", "开始写作即入定"),
        ("聚气", "字数 = 灵气；连更 = 经脉"),
        ("破境", "炼气 → 筑基 → 金丹 → 元婴"),
        ("功法与天劫", "成就 = 功法；完结长文 = 渡劫"),
    ]
    for i, (t, c) in enumerate(steps):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 210, "#0F1B16", "#8CFFC1", t, c)
        if i <= 1:
            d.ellipse([fx + 150, y + 110, fx + 250, y + 210], outline="#8CFFC1", width=5)
            d.arc([fx + 150, y + 110, fx + 250, y + 210], start=90, end=90 + (i + 1) * 110, fill="#FFD166", width=8)
        elif i == 2:
            d.ellipse([fx + 140, y + 100, fx + 260, y + 220], outline="#FFD166", width=6)
            label(d, (fx + 168, y + 144), "金丹", 20, "#FFD166", True)
        else:
            for k in range(3):
                d.line([(fx + 120 + k * 60, y + 110), (fx + 150 + k * 60, y + 210)], fill="#8CFFC1", width=4)
            label(d, (fx + 170, y + 150), "天劫", 20, "#FFD166", True)


def paper_garden(d, x, y):
    label(d, (x, y), "纸上花园 · PAPER GARDEN", 26, "#FF9FC6", True)
    label(d, (x, y + 34), "核心循环：写作 = 浇水 → 植物成长 → 花园开花 → 收集稀有植物与旅伴互动。", 15, "#D9A9BE")
    steps = [
        ("播种", "新建文档 = 种下一颗种子"),
        ("浇水", "输入与保存 → 水分与阳光"),
        ("成长", "连更让植物升级，闲置会休眠"),
        ("花期", "里程碑开花，收集稀有品种"),
    ]
    for i, (t, c) in enumerate(steps):
        fx = x + i * 430
        frame(d, fx, y + 70, 400, 210, "#241A20", "#FF9FC6", t, c)
        # 花盆与植物
        d.polygon([(fx + 170, y + 190), (fx + 230, y + 190), (fx + 218, y + 222), (fx + 182, y + 222)], fill="#8A5C4A")
        grow = [18, 42, 66, 84][i]
        d.line([(fx + 200, y + 190), (fx + 200, y + 190 - grow)], fill="#8CFFC1", width=5)
        d.ellipse([fx + 186, y + 176 - grow, fx + 214, y + 196 - grow],
                  fill=["#FF9FC6", "#FFD166", "#C98AFF", "#8CFFC1"][i])
        for leaf in (-1, 1):
            d.ellipse([fx + 200 + leaf * 20 - 10, y + 150 - grow // 2,
                       fx + 200 + leaf * 20 + 10, y + 166 - grow // 2], fill="#8CFFC1")


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/gamified-themes.png")
    img = Image.new("RGB", (W, H), "#0C1016")
    d = ImageDraw.Draw(img)
    label(d, (48, 32), "游戏化主题方向 · 写作会推进的玩法", 38, "#EAF2FF", True)
    label(d, (50, 86), "每行是一套独立游戏循环：数据本地计算，不联网；主题决定玩法、视觉、动效与成就。", 18, "#9FB3D9")
    quest_log(d, 48, 140)
    write_city(d, 48, 430)
    cultivation(d, 48, 720)
    paper_garden(d, 48, 1010)
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
