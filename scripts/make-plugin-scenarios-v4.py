#!/usr/bin/env python3
"""场景演示 v4：素材库按工作台隔离 + 卡片墙只做笔记 + 插件作用域规则。

用法: python3 scripts/make-plugin-scenarios-v4.py
"""

import importlib.util
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
v3 = _load("make-plugin-scenarios-v3")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P, MD = sc.P, sc.MD
mix, step_box, arrow = sc.mix, v3.step_box, v3.arrow


def sheet(title, oneline, win, steps, iso, out, accent, icon):
    W, H = 1840, 880
    img, d = gt.page(W, H)
    T(d, 48, 30, title, F(SONG, 28, 0), "#EFF4FF")
    d.rounded_rectangle([48, 76, 60, 108], radius=3, fill=accent)
    T(d, 74, 80, oneline, F(HIRA, 16, 2), P["text"])
    d.rounded_rectangle([W - 300, 40, W - 48, 82], radius=20, fill="#161C26", outline=accent)
    T(d, W - 174, 61, "第四轮细改 · 未实现", F(HIRA, 12), accent, anchor="mm")
    gt.paste_win(img, win, 48, 124, scale=0.60, radius=10, shadow=True)
    d.rounded_rectangle([48, 124, 48 + int(1300 * 0.60), 124 + int(800 * 0.60)],
                        radius=10, outline="#2A3648", width=1)
    T(d, 872, 124, "这个包到底在干什么", F(HIRA, 15, 2), accent)
    for i, (t, detail) in enumerate(steps):
        y = 158 + i * 112
        step_box(d, 872, y, 920, 100, i + 1, t, detail, accent, icon if i == 0 else None)
        if i < len(steps) - 1:
            arrow(d, 1320, y + 100 + 6, 26, accent)
    iso_h = 62 + len(iso) * 26 + 24
    top = 158 + len(steps) * 112 + 14
    d.rounded_rectangle([872, top, 1792, top + iso_h], radius=14, fill="#111722", outline="#1F2937")
    T(d, 894, top + 18, "隔离与作用域（插件规则）", F(HIRA, 15, 2), "#8FB8FF")
    for i, line in enumerate(iso):
        T(d, 894, top + 50 + i * 26, line, F(HIRA, 12.5), "#B9C6DC")
    img.save(out)
    print(out)


def win_base():
    return review.render_window(P).copy()


# 素材库 v4：按工作台隔离 + 单一触发
def scen_assets():
    win = win_base()
    d = ImageDraw.Draw(win)
    # 侧栏第三个 tab（素材）激活
    d.rounded_rectangle([14, 132, 42, 160], radius=8, fill=P["card"])
    d.rounded_rectangle([14, 178, 42, 206], radius=8, outline=P["line"])
    d.rounded_rectangle([14, 224, 42, 252], radius=8, fill=mix(P["bg"], MD["h1"], 0.28), outline=MD["h1"])
    T(d, 28, 238, "▦", F(HIRA, 13), MD["h1"], anchor="mm")
    # 素材面板
    d.rectangle([820, 0, 1300, 800], fill=P["bg"])
    d.line([(820, 0), (820, 800)], fill=P["line"])
    T(d, 846, 12, "素材", F(HIRA, 15, 2), P["text"])
    # 工作台选择器（作用域就写在这儿）
    d.rounded_rectangle([846, 38, 1120, 70], radius=9, fill=P["card"], outline=MD["h1"])
    T(d, 860, 46, "工作台  origin", F(HIRA, 12), P["text"])
    T(d, 1096, 46, "▾", F(HIRA, 12), P["--text-secondary"])
    d.rounded_rectangle([1132, 38, 1274, 70], radius=9, fill=P["card"], outline=P["line"])
    T(d, 1203, 54, "全部工作台（只读）", F(HIRA, 11), P["--text-secondary"], anchor="mm")
    T(d, 846, 82, "当前工作台的 source/ 资源 · 128 个 · 3 个未被引用", F(HIRA, 11), P["--text-secondary"])
    # 缩略图网格
    for i in range(6):
        col, row = i % 3, i // 3
        x, y = 846 + col * 146, 108 + row * 130
        d.rounded_rectangle([x, y, x + 132, y + 82], radius=8, fill=mix(P["bg"], MD["h3"], 0.20), outline=P["line"])
        T(d, x + 10, y + 56, f"09-1{i}-素材", F(HIRA, 10), P["text"])
        if i in (1, 4):
            d.rounded_rectangle([x + 86, y + 8, x + 124, y + 28], radius=6, fill=mix(P["bg"], MD["bold"], 0.30))
            T(d, x + 105, y + 18, "引用 2", F(HIRA, 9), MD["bold"], anchor="mm")
    # 选中条 + 唯一主动作
    d.rounded_rectangle([846, 382, 1274, 470], radius=10, fill=P["card"], outline=P["line"])
    T(d, 862, 394, "09-11-手绘线稿.png", F(HIRA, 12, 2), P["text"])
    T(d, 862, 418, "当前工作台内被 2 篇引用：周记 09 · 收件箱", F(HIRA, 10), P["--text-secondary"])
    d.rounded_rectangle([862, 436, 1002, 462], radius=9, fill=mix(P["bg"], MD["h1"], 0.30), outline=MD["h1"])
    T(d, 932, 449, "插入到光标处", F(HIRA, 11), MD["h1"], anchor="mm")
    T(d, 1074, 449, "⋯  在 Finder 显示 · 整理历史图（二级）", F(HIRA, 10), P["--text-secondary"])
    # 跨工作台复制说明
    d.rounded_rectangle([846, 486, 1274, 556], radius=10, fill=mix(P["bg"], MD["h2"], 0.14), outline=MD["h2"])
    T(d, 862, 496, "从别的拖进来？会自动复制到当前工作台", F(HIRA, 11, 2), MD["h2"])
    T(d, 862, 518, "跨工作台插入 = 拷贝一份到本工作台 source/，引用不会失效", F(HIRA, 10), P["--text-secondary"])
    T(d, 862, 536, "（切换工作台时，本面板自动换成那个工作台的素材）", F(HIRA, 10), P["--text-secondary"])
    # 编辑区：唯一触发 = 拖入/粘贴
    T_mix(d, 360, 420, "![手绘线稿](img/09-11-手绘线稿.png)", F(MONO, 13), F(HIRA, 13), MD["h1"])
    d.rounded_rectangle([346, 452, 800, 502], radius=10, fill=mix(P["bg"], MD["h1"], 0.16), outline=MD["h1"])
    T(d, 362, 462, "已存入 当前工作台/source/image/09-11-手绘线稿.png", F(HIRA, 11.5), MD["h1"])
    T(d, 362, 482, "⌘Z 撤销　·　不需要任何「导入」按钮", F(HIRA, 10), P["--text-secondary"])
    return win


# 卡片墙 v4：只做笔记
def scen_cards():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 12, "卡片墙 · 只显示笔记", F(HIRA, 15, 2), P["text"])
    # 工作台选择器（与素材库同一个组件）
    d.rounded_rectangle([358, 40, 560, 70], radius=9, fill=P["card"], outline=P["line"])
    T(d, 372, 48, "工作台  origin", F(HIRA, 12), P["text"])
    T(d, 536, 48, "▾", F(HIRA, 12), P["--text-secondary"])
    for i, t in enumerate(["树", "卡片"]):
        x = 576 + i * 76
        d.rounded_rectangle([x, 40, x + 68, 70], radius=9,
                            fill=P["card"] if i == 1 else None, outline=None if i == 1 else P["line"])
        T(d, x + 34, 55, t, F(HIRA, 11), P["text"] if i == 1 else P["--text-secondary"], anchor="mm")
    for i, t in enumerate(["最近", "带图", "未完成", "加星"]):
        x = 748 + i * 84
        d.rounded_rectangle([x, 40, x + 76, 70], radius=9,
                            fill=P["card"] if i == 0 else None, outline=None if i == 0 else P["line"])
        T(d, x + 38, 55, t, F(HIRA, 11), P["text"] if i == 0 else P["--text-secondary"], anchor="mm")
    groups = [("今天 · 09-12", [("《账目》产品设计文档", "记账的边界与验收标准…", MD["h1"], 0.72),
                               ("周记 09", "这周把主题做完，深林夜…", MD["h2"], 0.35)]),
              ("昨天 · 09-11", [("markdown 有哪些语法", "标题、粗体、列表、表格…", MD["h3"], 1.0),
                               ("配色评审记录", "青瓷灰 / 藕荷 / 沙金…", MD["math"], 0.18)])]
    y = 88
    for gname, cards in groups:
        T(d, 358, y + 10, gname, F(HIRA, 12, 2), P["--text-secondary"])
        d.line([(470, y + 20), (1272, y + 20)], fill=P["line"])
        for i, (title, summary, color, progress) in enumerate(cards):
            x = 358 + i * 462
            cy = y + 34
            d.rounded_rectangle([x, cy, x + 442, cy + 244], radius=14, fill=P["card"], outline=P["line"])
            d.rounded_rectangle([x, cy, x + 442, cy + 104], radius=14, fill=mix(P["bg"], color, 0.28))
            T(d, x + 16, cy + 120, title, F(HIRA, 15, 2), P["text"])
            T(d, x + 16, cy + 148, summary, F(HIRA, 12), P["--text-secondary"])
            d.rounded_rectangle([x + 16, cy + 178, x + 426, cy + 186], radius=4, fill=P["card2"])
            d.rounded_rectangle([x + 16, cy + 178, x + 16 + int(410 * progress), cy + 186], radius=4, fill=color)
            T(d, x + 16, cy + 194, f"上次读到 {int(progress * 100)}%　·　1,240 字", F(HIRA, 10), P["--text-secondary"])
            for j, (label, col) in enumerate([("继续写", color), ("加星", P["--text-secondary"]), ("归档", P["--text-secondary"])]):
                bx = x + 16 + j * 96
                d.rounded_rectangle([bx, cy + 214, bx + 84, cy + 238], radius=8, outline=col if j == 0 else P["line"])
                T(d, bx + 42, cy + 226, label, F(HIRA, 10), col if j == 0 else P["--text-secondary"], anchor="mm")
        y += 288
    d.rounded_rectangle([358, y + 8, 1272, y + 74], radius=10, fill=mix(P["bg"], MD["h2"], 0.12), outline=MD["h2"])
    T(d, 374, y + 18, "素材不在这里出现 —— 图片、PDF、录音都在「素材」面板里看", F(HIRA, 11.5, 2), MD["h2"])
    T(d, 374, y + 42, "卡片墙只回答一件事：我写过哪些笔记、哪些还没读完", F(HIRA, 11), P["--text-secondary"])
    return win


def main():
    outdir = ROOT / "docs/proposals/plugins"
    sheet("场景 ① · 素材库 v4（按工作台隔离 · 单一触发）",
          "一句话：素材跟着工作台走——切到哪个工作台就显示哪个工作台的图；唯一入口是「拖进来」。",
          scen_assets(),
          [("拖入 / 粘贴（唯一触发，没有「导入」按钮）",
            ["松手即入库：存进「当前工作台 / source/image」并自动按「日期-描述」命名"]),
           ("面板顶部就是作用域",
            ["默认「当前工作台」；下拉可切「全部工作台」——但那是只读浏览，不能跨库插入"]),
           ("插入 = 一行短引用",
            ["img/09-11-手绘线稿.png；跨工作台插入会自动复制一份到当前工作台，引用永不失效"])],
          ["作用域：默认「当前工作台」，切换工作台时面板自动跟着切",
           "只读：复用现有 source/ 扫描（不新建数据库、不扫无关目录）",
           "只写：当前工作台的 source/ 新建与重命名，每步可撤销",
           "不碰：编辑器内核、渲染管线、其他工作台的文件"],
          outdir / "v4-assets.png", MD["h1"], v3.icon_file)
    sheet("场景 ② · 卡片墙 v4（只做笔记）",
          "一句话：卡片墙是「笔记的回顾视图」——素材、附件、录音都不进来，它们属于素材库。",
          scen_cards(),
          [("侧栏顶部切「树 / 卡片」（同一个工作台选择器）",
            ["卡片墙只显示当前工作台的笔记，按「今天 / 昨天 / 更早」分组"]),
           ("卡片只写笔记的事",
            ["标题、摘要、字数、阅读进度；不显示素材缩略图，避免两套东西混在一起"]),
           ("悬浮就能继续写",
            ["继续写 / 加星 / 归档；长文显示「上次读到 72%」"])],
          ["作用域：与素材库同一个「当前工作台」，切工作台一起切",
           "只读：复用现有目录索引；星标只存本机偏好",
           "不写：不移动、不改名、不改笔记内容",
           "卸载即干净：切回文件树，一切照旧"],
          outdir / "v4-cards.png", MD["h2"], v3.icon_grid)


if __name__ == "__main__":
    main()
