#!/usr/bin/env python3
"""结构性主题方向提案：布局/导航/交互不同，而非换色。

用法: python3 scripts/make-structural-theme-proposals.py <out.png>
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

W, H = 1800, 1180
ZH = "/System/Library/Fonts/Hiragino Sans GB.ttc"


def font(size, bold=False):
    try:
        # 系统黑体足够表达结构示意
        return ImageFont.truetype(ZH, size, index=1 if bold else 0)
    except Exception:
        return ImageFont.load_default()


def panel(d, box, fill, outline, radius=18):
    d.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=2)


def label(d, xy, text, size=16, color="#EAF2FF", bold=False):
    d.text(xy, text, font=font(size, bold), fill=color)


def obsidian(d, x, y, w, h):
    panel(d, [x, y, x + w, y + h], "#07131C", "#38E8FF")
    label(d, (x + 22, y + 18), "星图 · OBSERVATORY", 20, "#38E8FF", True)
    label(d, (x + 22, y + 48), "导航 = 星图节点；文件=星体；链接=星线；预览=望远镜视口", 14, "#8FB6C9")
    # 星图导航
    panel(d, [x + 22, y + 84, x + 300, y + h - 24], "#0C2130", "#1E5A74")
    nodes = [(90, 150), (190, 190), (120, 260), (240, 300), (170, 360), (250, 420)]
    for a, b in [(0, 1), (0, 2), (1, 3), (2, 4), (3, 5), (4, 5)]:
        d.line([x + nodes[a][0], y + nodes[a][1], x + nodes[b][0], y + nodes[b][1]], fill="#2E7D96", width=2)
    for i, (nx, ny) in enumerate(nodes):
        r = 12 if i in (0, 4) else 8
        d.ellipse([x + nx - r, y + ny - r, x + nx + r, y + ny + r],
                  fill="#38E8FF" if i in (0, 4) else "#7CFFB2")
    # 编辑与预览
    panel(d, [x + 324, y + 84, x + w - 22, y + h - 24], "#0A1A26", "#1E5A74")
    d.line([(x + 324, y + 120), (x + w - 22, y + 120)], fill="#1E5A74", width=2)
    for i, ww in enumerate([w - 90, w - 140, w - 70]):
        d.rounded_rectangle([x + 350, y + 150 + i * 26, x + 350 + ww, y + 160 + i * 26], radius=4, fill="#8FB6C9")
    d.rectangle([x + 350, y + 240, x + w - 60, y + 260], fill="#38E8FF44")
    label(d, (x + 350, y + 290), "constellation.connect(note)", 15, "#7CFFB2")


def letterpress(d, x, y, w, h):
    panel(d, [x, y, x + w, y + h], "#F4ECDD", "#8E2C3A")
    label(d, (x + 22, y + 18), "活字工坊 · LETTERPRESS", 20, "#8E2C3A", True)
    label(d, (x + 22, y + 48), "导航 = 铅字盘；编辑 = 排版台；预览 = 印刷校样；操作 = 压印", 14, "#6E5B4A")
    panel(d, [x + 22, y + 84, x + 300, y + h - 24], "#E8DCC7", "#8E2C3A")
    for r in range(5):
        for c in range(3):
            bx, by = x + 40 + c * 82, y + 106 + r * 74
            d.rounded_rectangle([bx, by, bx + 64, by + 56], radius=6, fill="#FBF6EC", outline="#8E2C3A", width=2)
            label(d, (bx + 18, by + 16), "字", 20, "#2B211A", True)
    # 排版台
    panel(d, [x + 324, y + 84, x + w - 22, y + 390], "#FBF6EC", "#B7A184")
    d.rounded_rectangle([x + 360, y + 120, x + w - 60, y + 350], radius=10, fill="#FFFDF8", outline="#8E2C3A", width=2)
    for i, ww in enumerate([w - 150, w - 190, w - 120]):
        d.rounded_rectangle([x + 390, y + 160 + i * 30, x + 390 + ww, y + 170 + i * 30], radius=4, fill="#2B211A66")
    d.rounded_rectangle([x + 390, y + 270, x + w - 90, y + 330], radius=8, fill="#F0E5D2", outline="#B7A184", width=2)
    label(d, (x + 410, y + 288), "metal type · proof", 15, "#6E5B4A")
    # 压印台
    panel(d, [x + 324, y + 410, x + w - 22, y + h - 24], "#EFE3CE", "#8E2C3A")
    label(d, (x + 350, y + 430), "PRESS 压印", 16, "#8E2C3A", True)
    d.rounded_rectangle([x + 350, y + 470, x + w - 60, y + 540], radius=10, fill="#FBF6EC", outline="#B7A184", width=2)
    d.rounded_rectangle([x + w - 180, y + 480, x + w - 70, y + 530], radius=8, fill="#8E2C3A")


def terminal(d, x, y, w, h):
    panel(d, [x, y, x + w, y + h], "#07100C", "#7CFFB2")
    label(d, (x + 22, y + 18), "终端甲板 · TERMINAL DECK", 20, "#7CFFB2", True)
    label(d, (x + 22, y + 48), "导航 = 命令轨道；页签 = 会话通道；编辑 = 控制台；预览 = 监视器", 14, "#9AC9AE")
    # 命令轨
    panel(d, [x + 22, y + 84, x + 260, y + h - 24], "#0B1A13", "#2F7F5F")
    for i, cmd in enumerate(["> workspace", "> plugins", "> search", "> versions"]):
        yy = y + 110 + i * 44
        if i == 0:
            d.rounded_rectangle([x + 34, yy - 8, x + 248, yy + 26], radius=6, fill="#7CFFB222")
        label(d, (x + 46, yy), cmd, 15, "#7CFFB2" if i == 0 else "#9AC9AE")
    # 控制台
    panel(d, [x + 284, y + 84, x + w - 22, y + h - 24], "#050B08", "#2F7F5F")
    for i, line in enumerate(["$ launch --theme terminal", "> connecting...", "> session ready", ""]):
        label(d, (x + 310, y + 116 + i * 34), line, 16, "#7CFFB2" if i < 2 else "#D7FFE6")
    d.rectangle([x + 310, y + 270, x + 330, y + 292], fill="#7CFFB2")
    d.rounded_rectangle([x + 310, y + 330, x + w - 60, y + 400], radius=8, fill="#0B1A13", outline="#2F7F5F", width=2)
    label(d, (x + 330, y + 352), "MONITOR  1984", 15, "#7CFFB2")


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/structural-themes.png")
    img = Image.new("RGB", (W, H), "#0B0F16")
    d = ImageDraw.Draw(img)
    label(d, (48, 32), "结构性主题方向 · 不换皮，换骨架", 38, "#EAF2FF", True)
    label(d, (50, 86), "核心差异：导航方式 / 面板结构 / 交互模型 / 动效语言 —— 不是配色差异", 18, "#9FB3D9")
    obsidian(d, 40, 130, 560, 1000)
    letterpress(d, 620, 130, 560, 1000)
    terminal(d, 1200, 130, 560, 1000)
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
