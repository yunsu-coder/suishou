#!/usr/bin/env python3
"""场景演示 v3：一句话说清 + 三步主流程 + 插件隔离边界。

三个场景：素材库 / 卡片墙 / 阅读专注态（已砍掉「文档体检」）
用法: python3 scripts/make-plugin-scenarios-v3.py
"""

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gt = _load("make-game-themes")
review = _load("make-misty-teal-review")
sc = _load("make-plugin-scenarios")
v2 = _load("make-plugin-scenarios-v2")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P, MD = sc.P, sc.MD
mix = sc.mix


def arrow(d, x, y, w=26, color=None):
    c = color or P["--text-secondary"]
    d.line([(x, y), (x + w - 8, y)], fill=c, width=2)
    d.polygon([(x + w - 8, y - 5), (x + w, y), (x + w - 8, y + 5)], fill=c)


def step_box(d, x, y, w, h, n, title, detail, accent, icon=None):
    d.rounded_rectangle([x, y, x + w, y + h], radius=12, fill=P["card"], outline=P["line"])
    d.ellipse([x + 16, y + 16, x + 44, y + 44], fill=accent)
    T(d, x + 30, y + 30, str(n), F(HIRA, 15, 2), "#0E1512", anchor="mm")
    T(d, x + 56, y + 18, title, F(HIRA, 15, 2), P["text"])
    for i, line in enumerate(detail):
        T(d, x + 56, y + 46 + i * 22, line, F(HIRA, 12), P["--text-secondary"])
    if icon:
        icon(d, x + w - 76, y + 30, 40, mix(P["bg"], accent, 0.55))


def icon_file(d, x, y, s, c):
    d.rounded_rectangle([x, y, x + s * 0.72, y + s], radius=5, outline=c, width=2)
    d.polygon([(x + s * 0.34, y + s * 0.28), (x + s * 0.62, y + s * 0.5),
               (x + s * 0.34, y + s * 0.72)], fill=c)


def icon_window(d, x, y, s, c):
    d.rounded_rectangle([x, y, x + s, y + s * 0.82], radius=5, outline=c, width=2)
    d.line([(x, y + s * 0.22), (x + s, y + s * 0.22)], fill=c, width=2)
    for k in range(3):
        d.line([(x + 5, y + s * (0.42 + k * 0.16)), (x + s - 8, y + s * (0.42 + k * 0.16))], fill=c, width=2)


def icon_grid(d, x, y, s, c):
    for i in range(4):
        cx = x + (i % 2) * (s * 0.56)
        cy = y + (i // 2) * (s * 0.56)
        d.rounded_rectangle([cx, cy, cx + s * 0.44, cy + s * 0.44], radius=4, outline=c, width=2)


def icon_focus(d, x, y, s, c):
    d.rounded_rectangle([x + s * 0.22, y, x + s * 0.78, y + s], radius=5, outline=c, width=2)
    for k in range(4):
        d.line([(x + s * 0.3, y + s * (0.2 + k * 0.2)), (x + s * 0.7, y + s * (0.2 + k * 0.2))], fill=c, width=2)
    d.line([(x, y + s * 0.36), (x + s * 0.16, y + s * 0.36)], fill=c, width=3)
    d.line([(x, y + s * 0.64), (x + s * 0.16, y + s * 0.64)], fill=c, width=3)
    d.line([(x + s * 0.84, y + s * 0.36), (x + s, y + s * 0.36)], fill=c, width=3)
    d.line([(x + s * 0.84, y + s * 0.64), (x + s, y + s * 0.64)], fill=c, width=3)


def sheet(title, oneline, win, steps, iso, out, accent, icon):
    W, H = 1840, 780
    img, d = gt.page(W, H)
    T(d, 48, 30, title, F(SONG, 28, 0), "#EFF4FF")
    d.rounded_rectangle([48, 76, 48 + 12, 108], radius=3, fill=accent)
    T(d, 74, 80, oneline, F(HIRA, 16, 2), P["text"])
    d.rounded_rectangle([W - 300, 40, W - 48, 82], radius=20, fill="#161C26", outline=accent)
    T(d, W - 174, 61, "场景演示 · 未实现", F(HIRA, 12), accent, anchor="mm")

    gt.paste_win(img, win, 48, 124, scale=0.60, radius=10, shadow=True)
    d.rounded_rectangle([48, 124, 48 + int(1300 * 0.60), 124 + int(800 * 0.60)],
                        radius=10, outline="#2A3648", width=1)

    # 三步主流程（横向，大框）
    T(d, 872, 124, "这个包到底在干什么（三步）", F(HIRA, 15, 2), accent)
    for i, (t, detail) in enumerate(steps):
        y = 158 + i * 118
        step_box(d, 872, y, 920, 104, i + 1, t, detail, accent, icon if i == 0 else None)
        if i < len(steps) - 1:
            arrow(d, 1320, y + 104 + 6, 26, accent)

    iso_h = 62 + len(iso) * 26 + 26
    d.rounded_rectangle([872, 516, 1792, 516 + iso_h], radius=14, fill="#111722", outline="#1F2937")
    T(d, 894, 534, "插件隔离边界（它是插件，不是改内核）", F(HIRA, 15, 2), "#8FB8FF")
    for i, line in enumerate(iso):
        T(d, 894, 566 + i * 26, line, F(HIRA, 12.5), "#B9C6DC")
    img.save(out)
    print(out)


def main():
    outdir = ROOT / "docs/proposals/plugins"
    outdir.mkdir(parents=True, exist_ok=True)
    sheet("场景 ① · 素材库",
          "一句话：图片不用你管路径——拖进来就自动入库、自动命名，笔记里只留一行短引用。",
          v2.scen_assets(),
          [("把图拖进笔记窗口（或 ⌘V 粘贴）",
            ["松手即可，不弹窗、不打断打字；编辑区只出现一条可撤销的轻提示"]),
           ("插件自动做三件事",
            ["存进 source/img　·　命名成「日期-描述」　·　在光标处插入短引用 img/xxx.png"]),
           ("以后要找就用侧栏「素材」",
            ["搜索、看被哪几篇引用（防误删）、一键整理历史乱名图片（先给 diff）"])],
          ["只读：目录索引（不扫描无关文件）",
           "只写：source/ 下新建与重命名，且每步可撤销",
           "不碰：编辑器内核、渲染管线、别人的笔记内容",
           "卸载即干净：已插入的短引用仍是标准 Markdown（只是图片还在 source/img）"],
          outdir / "v3-assets.png", MD["h1"], icon_file)
    sheet("场景 ② · 卡片墙",
          "一句话：把文件树换成「按天排的卡片墙」，适合回顾；找文件还是用树。",
          v2.scen_cards(),
          [("点侧栏顶部的「树 / 卡片」切换",
            ["一个开关，不是新模式；切回树只影响显示，不动任何文件"]),
           ("笔记变成按天分组的卡片",
            ["今天 / 昨天 / 更早　·　卡片上有封面、摘要、字数、图片数"]),
           ("悬浮卡片直接操作",
            ["继续写 / 加星 / 归档；长文显示「上次读到 72%」，没读完的自己浮出来"])],
          ["只读：复用现有目录索引，不新建数据库",
           "不写：不移动、不改名、不改笔记内容（星标只存本机偏好）",
           "渲染：卡片颜色与字体跟随当前主题（复用主题系统，不重复造）",
           "卸载即干净：切回文件树，一切照旧"],
          outdir / "v3-cards.png", MD["h2"], icon_grid)
    sheet("场景 ③ · 阅读专注态",
          "一句话：它不是新模式，是「预览」的一档宽度状态——左栏淡出、单栏居中，Esc 就回来。",
          v2.scen_reader(),
          [("进入：双击预览空白 / ⌘⇧R / 视图菜单",
            ["默认手动触发；「滚动一屏 + 5 秒无输入自动进入」是可开关的选项"]),
           ("专注中：左栏淡出，正文单栏居中",
            ["浮动大纲只在滚动时出现；阅读位置自动记住（下次回到原处）"]),
           ("退出：Esc / 鼠标到顶部 8px / 按编辑键",
            ["工具条与左栏同时回来，光标位置不变"]),
           ],
          ["只改「看得见什么」：预览面板的宽度与左栏可见性",
           "不碰：排版规则、渲染结果、文档内容、光标与选区",
           "状态只存本机偏好（每篇的阅读位置），不进笔记文件",
           "与主题解耦：排版仍由主题决定，它只管「露出多少」"],
          outdir / "v3-reader.png", MD["h3"], icon_focus)


if __name__ == "__main__":
    main()
