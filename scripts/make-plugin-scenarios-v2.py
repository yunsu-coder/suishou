#!/usr/bin/env python3
"""场景演示 · 第二轮细改：素材库 / 卡片墙 / 阅读专注态 / 待补清单。

用法: python3 scripts/make-plugin-scenarios-v2.py
输出: docs/proposals/plugins/v2-*.png
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
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P, MD = sc.P, sc.MD
mix = sc.mix


def sheet(title, sub, changes, win, out, accent, extra=None):
    W, H = 1840, 700
    img, d = gt.page(W, H)
    T(d, 48, 30, title, F(SONG, 28, 0), "#EFF4FF")
    T(d, 50, 76, sub, F(HIRA, 14), "#93A3BE")
    d.rounded_rectangle([W - 320, 40, W - 48, 82], radius=20, fill="#161C26", outline=accent)
    T(d, W - 184, 61, "第二轮细改 · 未实现", F(HIRA, 12), accent, anchor="mm")
    gt.paste_win(img, win, 48, 116, scale=0.60, radius=10, shadow=True)
    d.rounded_rectangle([48, 116, 48 + int(1300 * 0.60), 116 + int(800 * 0.60)],
                        radius=10, outline="#2A3648", width=1)
    sx = 872
    d.rounded_rectangle([sx, 116, W - 48, 420], radius=14, fill="#111722", outline="#1F2937")
    T(d, sx + 22, 134, "这一版改了什么", F(HIRA, 14, 2), accent)
    for i, (before, after) in enumerate(changes):
        y = 166 + i * 46
        T(d, sx + 22, y, "改前", F(HIRA, 10, 2), "#8FA0BB")
        T(d, sx + 66, y, before, F(HIRA, 11.5), "#7E8DA6")
        T(d, sx + 22, y + 20, "改后", F(HIRA, 10, 2), accent)
        T(d, sx + 66, y + 20, after, F(HIRA, 12), P["text"])
    if extra:
        d.rounded_rectangle([sx, 436, W - 48, 660], radius=14, fill="#111722", outline="#1F2937")
        T(d, sx + 22, 454, extra[0], F(HIRA, 14, 2), accent)
        for i, line in enumerate(extra[1]):
            T(d, sx + 22, 484 + i * 26, line, F(HIRA, 12), "#B9C6DC")
    img.save(out)
    print(out)


def win_base():
    return review.render_window(P).copy()


# ① 素材库 v2
def scen_assets():
    win = win_base()
    d = ImageDraw.Draw(win)
    # 侧栏加第三个 tab：素材（与文件树并列，不抢编辑宽度）
    d.rounded_rectangle([14, 132, 42, 160], radius=8, fill=P["card"])
    d.rounded_rectangle([14, 178, 42, 206], radius=8, outline=P["line"])
    d.rounded_rectangle([14, 224, 42, 252], radius=8, fill=mix(P["bg"], MD["h1"], 0.28), outline=MD["h1"])
    T(d, 28, 238, "▦", F(HIRA, 13), MD["h1"], anchor="mm")
    # 素材面板（替换预览区，但顶部标出「从侧栏进入」）
    d.rectangle([820, 0, 1300, 800], fill=P["bg"])
    d.line([(820, 0), (820, 800)], fill=P["line"])
    T(d, 846, 14, "素材 · 只显示「未被引用」", F(HIRA, 14, 2), P["text"])
    T(d, 846, 40, "128 张 · 3 张未被引用 · 2 张文件名不规范", F(HIRA, 11), P["--text-secondary"])
    for i, t in enumerate(["全部", "未引用", "不规范", "最近"]):
        x = 846 + i * 78
        d.rounded_rectangle([x, 62, x + 70, 86], radius=8,
                            fill=P["card"] if i == 1 else None, outline=None if i == 1 else P["line"])
        T(d, x + 35, 74, t, F(HIRA, 10), P["text"] if i == 1 else P["--text-secondary"], anchor="mm")
    # 一键整理卡片
    d.rounded_rectangle([846, 98, 1274, 186], radius=10, fill=mix(P["bg"], MD["h2"], 0.14), outline=MD["h2"])
    T(d, 862, 110, "一键整理历史图片", F(HIRA, 12, 2), MD["h2"])
    T(d, 862, 132, "IMG_2043.PNG → 09-05-配色稿.png", F(MONO, 11), P["text"])
    T(d, 862, 150, "long/path/…/IMG_2044.PNG → 09-08-流程图.png", F(MONO, 11), P["text"])
    T(d, 862, 168, "会同时改好 12 篇笔记里的引用（先给你 diff 预览）", F(HIRA, 10), P["--text-secondary"])
    # 缩略图（含被引用的标记）
    for i in range(6):
        col, row = i % 3, i // 3
        x, y = 846 + col * 146, 200 + row * 132
        d.rounded_rectangle([x, y, x + 132, y + 84], radius=8, fill=mix(P["bg"], MD["h3"], 0.20), outline=P["line"])
        T(d, x + 10, y + 58, f"09-1{i}-素材", F(HIRA, 10), P["text"])
        if i in (1, 4):
            d.rounded_rectangle([x + 88, y + 8, x + 124, y + 28], radius=6, fill=mix(P["bg"], MD["bold"], 0.30))
            T(d, x + 106, y + 18, "被引用 2", F(HIRA, 9), MD["bold"], anchor="mm")
    d.rounded_rectangle([846, 476, 1274, 552], radius=10, fill=P["card"], outline=P["line"])
    T(d, 862, 488, "选中：09-11-手绘线稿.png", F(HIRA, 12, 2), P["text"])
    T(d, 862, 512, "被 2 篇引用：周记 09 · 收件箱　｜　删除前会提示位置", F(HIRA, 10), P["--text-secondary"])
    T(d, 862, 532, "插入到当前笔记　·　复制短引用　·　在 Finder 显示", F(HIRA, 10), MD["h2"])
    # 编辑区：插入不打断（胶囊提示 + 可撤销）
    d.rounded_rectangle([346, 470, 800, 520], radius=10, fill=mix(P["bg"], MD["h1"], 0.16), outline=MD["h1"])
    T(d, 362, 480, "已插入「09-11-手绘线稿.png」到光标处", F(HIRA, 12), MD["h1"])
    T(d, 362, 500, "⌘Z 撤销　·　不再写长路径，短引用 img/09-11-手绘线稿.png", F(HIRA, 10), P["--text-secondary"])
    T_mix(d, 360, 424, "![手绘线稿](img/09-11-手绘线稿.png)", F(MONO, 13), F(HIRA, 13), MD["h1"])
    return win


# ② 卡片墙 v2
def scen_cards():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 14, "卡片墙", F(HIRA, 17, 2), P["text"])
    # 树 / 卡片切换放在侧栏顶部
    d.rounded_rectangle([66, 82, 200, 112], radius=9, fill=P["card"], outline=P["line"])
    T(d, 96, 97, "树", F(HIRA, 11), P["--text-secondary"], anchor="mm")
    d.rounded_rectangle([132, 84, 198, 110], radius=8, fill=mix(P["bg"], MD["h2"], 0.30))
    T(d, 165, 97, "卡片", F(HIRA, 11), P["text"], anchor="mm")
    for i, t in enumerate(["最近", "带图", "未完成", "加星"]):
        x = 470 + i * 86
        d.rounded_rectangle([x, 14, x + 78, 40], radius=9,
                            fill=P["card"] if i == 0 else None, outline=None if i == 0 else P["line"])
        T(d, x + 39, 27, t, F(HIRA, 11), P["text"] if i == 0 else P["--text-secondary"], anchor="mm")
    groups = [("今天 · 09-12", [("《账目》产品设计文档", "记账的边界与验收标准…", MD["h1"], 0.72, "3 张图"),
                               ("周记 09", "这周把主题做完，深林夜…", MD["h2"], 0.35, "1 张图")]),
              ("昨天 · 09-11", [("markdown 有哪些语法", "标题、粗体、列表、表格…", MD["h3"], 1.0, ""),
                                ("配色评审记录", "青瓷灰 / 藕荷 / 沙金…", MD["math"], 0.18, "4 张图")])]
    y = 62
    for gname, cards in groups:
        T(d, 358, y + 12, gname, F(HIRA, 12, 2), P["--text-secondary"])
        d.line([(470, y + 22), (1272, y + 22)], fill=P["line"])
        for i, (title, summary, color, progress, imgs) in enumerate(cards):
            x = 358 + i * 462
            cy = y + 40
            d.rounded_rectangle([x, cy, x + 442, cy + 268], radius=14, fill=P["card"], outline=P["line"])
            d.rounded_rectangle([x, cy, x + 442, cy + 118], radius=14, fill=mix(P["bg"], color, 0.28))
            T(d, x + 16, cy + 92, imgs or "无图", F(HIRA, 10), P["text"])
            T(d, x + 16, cy + 134, title, F(HIRA, 15, 2), P["text"])
            T(d, x + 16, cy + 162, summary, F(HIRA, 12), P["--text-secondary"])
            # 阅读进度（上次读到哪里）
            d.rounded_rectangle([x + 16, cy + 196, x + 426, cy + 204], radius=4, fill=P["card2"])
            d.rounded_rectangle([x + 16, cy + 196, x + 16 + int(410 * progress), cy + 204], radius=4, fill=color)
            T(d, x + 16, cy + 212, f"上次读到 {int(progress * 100)}%　·　1,240 字", F(HIRA, 10), P["--text-secondary"])
            # 悬浮快捷动作
            for j, (label, col) in enumerate([("继续写", color), ("加星", P["--text-secondary"]), ("归档", P["--text-secondary"])]):
                bx = x + 16 + j * 96
                d.rounded_rectangle([bx, cy + 236, bx + 84, cy + 260], radius=8, outline=col if j == 0 else P["line"])
                T(d, bx + 42, cy + 248, label, F(HIRA, 10), col if j == 0 else P["--text-secondary"], anchor="mm")
        y += 320
    return win


# ③ 阅读专注态（三种触发方案）
def scen_reader():
    win = win_base()
    d = ImageDraw.Draw(win)
    # 分三帧：正常 → 专注中 → 退出提示
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 16, "预览的「专注态」——不是新模式，是预览的一档状态", F(HIRA, 14, 2), P["text"])
    frames = [("触发前", "预览正常，左栏在", 0), ("专注中", "左栏淡出，单栏居中", 1), ("退出", "鼠标移到顶部 → 工具条回来", 2)]
    for i, (name, hint, state) in enumerate(frames):
        x = 358 + i * 316
        y = 52
        d.rounded_rectangle([x, y, x + 288, y + 600], radius=14, fill=P["card"], outline=P["line"])
        T(d, x + 14, y + 12, name, F(HIRA, 13, 2), MD["h1"] if state == 1 else P["text"])
        T(d, x + 14, y + 36, hint, F(HIRA, 10), P["--text-secondary"])
        # 模拟窗口：左栏 + 正文
        lx = x + 14
        if state != 1:
            d.rectangle([lx, y + 60, lx + 70, y + 560], fill=P["sidebar"])
            for k in range(6):
                d.rounded_rectangle([lx + 8, y + 78 + k * 22, lx + 62, y + 92 + k * 22], radius=4,
                                    fill=mix(P["bg"], P["text"], 0.10))
        bx = x + 14 if state == 1 else lx + 82
        bw = 260 if state == 1 else 188
        d.rounded_rectangle([bx, y + 60, bx + bw, y + 560], radius=8, fill=P["bg"], outline=P["line"])
        if state == 2:
            d.rounded_rectangle([bx, y + 64, bx + bw, y + 92], radius=8, fill=P["card"], outline=P["line"])
            T(d, bx + 10, y + 72, "退出专注  Esc", F(HIRA, 10), P["--text-secondary"])
        T(d, bx + 14, y + 84, "《账目》产品设计文档", F(HIRA, 12, 2), P["text"])
        for k in range(9):
            d.rounded_rectangle([bx + 14, y + 116 + k * 26, bx + bw - 20 - (k % 3) * 26, y + 128 + k * 26],
                                radius=4, fill=mix(P["bg"], P["text"], 0.55 if k % 3 != 2 else 0.3))
    # 触发方案
    T(d, 358, 674, "三种触发方案（我推荐 A + C）", F(HIRA, 13, 2), "#EFF4FF")
    plans = [("A 手动", "双击预览空白 / ⌘⇧R / 视图菜单"),
             ("B 自动", "滚动超一屏 + 5 秒无输入 → 左栏淡出（可关）"),
             ("C 退出", "Esc / 鼠标到顶部 8px / 按编辑键")]
    for i, (k, v) in enumerate(plans):
        d.rounded_rectangle([358 + i * 316, 700, 358 + i * 316 + 300, 776], radius=10,
                            fill=P["card"], outline=P["line"])
        T(d, 372 + i * 316, 712, k, F(HIRA, 12, 2), MD["h1"])
        T(d, 372 + i * 316, 734, v, F(HIRA, 10), P["--text-secondary"])
    return win


# ④ 待补清单 + 结构概览（取代"文档体检"）
def scen_todo():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rectangle([980, 0, 1300, 766], fill=P["bg"])
    d.line([(980, 0), (980, 766)], fill=P["line"])
    T(d, 1002, 14, "待补清单", F(HIRA, 14, 2), P["text"])
    T(d, 1002, 38, "只汇总「你自己标了没写完」的地方", F(HIRA, 10), P["--text-secondary"])
    todos = [("第 12 行", "验收标准：TODO 补三档", MD["bold"]),
             ("第 18 行", "？这里数据来源还要确认", MD["italic"]),
             ("第 24 行", "待补：字段表", MD["italic"]),
             ("第 31 行", "「四、风险」是空章节", MD["h2"]),
             ("第 40 行", "图片缺图注（可选）", P["--text-secondary"])]
    for i, (loc, text, color) in enumerate(todos):
        y = 70 + i * 62
        d.rounded_rectangle([1002, y, 1278, y + 54], radius=10, fill=P["card"], outline=P["line"])
        d.rounded_rectangle([1002, y, 1006, y + 54], radius=2, fill=color)
        T(d, 1018, y + 8, text, F(HIRA, 12), P["text"])
        T(d, 1018, y + 30, loc, F(HIRA, 10), P["--text-secondary"])
        d.rounded_rectangle([1196, y + 26, 1266, y + 48], radius=8, outline=color)
        T(d, 1231, y + 37, "跳过去", F(HIRA, 10), color, anchor="mm")
    # 结构概览
    d.rounded_rectangle([1002, 390, 1278, 566], radius=12, fill=P["card"], outline=P["line"])
    T(d, 1018, 404, "结构概览", F(HIRA, 12, 2), P["text"])
    struct = [("一、产品边界", 320, True), ("二、第一版三件事", 480, True),
              ("三、输入方式", 260, True), ("四、风险", 0, False), ("五、验收标准", 120, False)]
    for i, (name, words, done) in enumerate(struct):
        y = 430 + i * 26
        d.rounded_rectangle([1030, y + 4, 1042, y + 16], radius=6,
                            fill=MD["insert"] if done else P["card2"], outline=P["line"])
        T(d, 1052, y, name, F(HIRA, 11), P["text"])
        T(d, 1180, y, f"{words} 字", F(HIRA, 10), P["--text-secondary"])
        if not done:
            d.rounded_rectangle([1216, y - 2, 1266, y + 18], radius=6, fill=mix(P["bg"], MD["bold"], 0.25))
            T(d, 1241, y + 8, "待补", F(HIRA, 9), MD["bold"], anchor="mm")
    T(d, 1018, 576, "「这篇写完了吗」→ 4 个章节已完成，2 处待补", F(HIRA, 11), MD["insert"])
    # 状态栏徽标 + 编辑区标记
    d.rounded_rectangle([1244, 776, 1292, 798], radius=10, fill=mix(P["bg"], MD["bold"], 0.30))
    T(d, 1268, 787, "待补 4", F(HIRA, 10), MD["bold"], anchor="mm")
    T_mix(d, 360, 296, "### 验收标准　TODO 补三档", F(MONO, 13), F(HIRA, 13), MD["h3"])
    T_mix(d, 360, 330, "？这里数据来源还要确认", F(MONO, 13), F(HIRA, 13), MD["italic"])
    return win


def main():
    outdir = ROOT / "docs/proposals/plugins"
    outdir.mkdir(parents=True, exist_ok=True)
    sheet("细改 ① · 素材库 v2（少打断、能收拾历史）",
          "上一版只解决「入库」；这一版解决「写的时候别被打断」和「以前那堆乱图怎么办」。",
          [("入库后弹一个全屏确认框", "入库只在编辑区给一条可撤销的轻提示（⌘Z）"),
           ("只在素材面板里找图", "侧栏第三个 tab 进入素材，不抢编辑宽度"),
           ("历史乱名/长路径没法处理", "一键整理：重命名 + 修好 12 篇笔记的引用（先出 diff）"),
           ("删图可能删掉别处还在用的", "面板显示「被引用 N」，删除前列出引用位置")],
          scen_assets(), outdir / "v2-assets.png", MD["h1"],
          extra=("插入后的样子", ["![手绘线稿](img/09-11-手绘线稿.png)",
                                "· 目录前缀固定：img/ 就是 source/img/，不用写全路径",
                                "· 文件名由「日期-描述」生成，短、可读、不会重名"]))
    sheet("细改 ② · 卡片墙 v2（按时间分组 + 上次读到哪里）",
          "上一版只是网格；这一版让它真的能「回顾」：按天分组、带阅读进度、悬浮就能继续写。",
          [("所有卡片一样大、没有分组", "按「今天 / 昨天 / 更早」分组，滚动时分组标题吸顶"),
           ("不知道上一篇读到哪", "卡片上带阅读进度条 +「上次读到 72%」"),
           ("点开才能操作", "悬浮出现：继续写 / 加星 / 归档"),
           ("入口藏在菜单里", "侧栏顶部直接切换「树 / 卡片」")],
          scen_cards(), outdir / "v2-cards.png", MD["h2"],
          extra=("为什么这样更好回顾", ["· 分组标题给了「时间感」——回忆靠的是时间线，不是文件名",
                                      "· 阅读进度让「没读完的长文」自己浮出来",
                                      "· 卡片颜色与字体跟随当前主题，切换主题整墙一起变"]))
    sheet("细改 ③ · 阅读专注态（重点改触发逻辑）",
          "你指出它其实是「预览的简洁版」——对。所以不做新模式，改成预览的一档状态，并把触发说清楚。",
          [("当成独立模式，要记一个新快捷键", "就是预览的专注态：双击预览空白处 / ⌘⇧R / 视图菜单"),
           ("进去后不知道怎么退", "Esc、鼠标移到顶部 8px、或按任意编辑键 → 工具条与左栏同时回来"),
           ("每次都要手动开", "可选自动：预览里滚动超过一屏且 5 秒无输入 → 左栏淡出（设置里可关）"),
           ("读完再打开忘了读到哪", "自动记住每篇的阅读位置与最后停留章节")],
          scen_reader(), outdir / "v2-reader.png", MD["h3"],
          extra=("和「预览」的关系", ["· 预览：一直在，带工具栏与左栏 —— 适合边写边看",
                                   "· 专注态：预览的一种宽度状态（左栏淡出、单栏居中）",
                                   "· 不动数据、不动排版规则，只改「看得见什么」"]))
    sheet("细改 ④ · 待补清单（替掉「文档体检」）",
          "上一版像 lint，在挑错；改成只回答一个问题：这篇写完了吗。不常驻、不打扰。",
          [("常驻面板列问题，像 IDE 报错", "只在状态栏留一个徽标「待补 4」，点开才展开"),
           ("它替我判断对错（标题层级该不该跳）", "只汇总「你自己标的」：TODO / ？ / 待补 / 空章节"),
           ("没有任何结构感", "同时给一张结构概览：章节字数 + 哪几节还是空的"),
           ("导出前不会提醒", "导出或分享前提示一次「还有 4 处待补」，可一键忽略")],
          scen_todo(), outdir / "v2-todo.png", MD["bold"],
          extra=("触发与克制", ["· 平时完全不出现在正文区（只在状态栏有个小徽标）",
                             "· 只在两种时刻主动说话：打开一篇「有 ≥3 处待补」的文档、导出前",
                             "· 不检查错别字、不检查语法——那是另一个包的事"]))


if __name__ == "__main__":
    main()
