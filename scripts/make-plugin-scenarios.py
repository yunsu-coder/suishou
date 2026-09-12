#!/usr/bin/env python3
"""插件包 · 场景演示稿：在真实窗口布局里画出「装上以后是什么样」。

四个场景：素材库 / 卡片墙 / 阅读模式 / 文档体检
用法: python3 scripts/make-plugin-scenarios.py
输出: docs/proposals/plugins/scenario-*.png
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
fn = _load("make-forest-night")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P = fn.P                      # 用你已选的深林夜做底
MD = P["md"]


def mix(a, b, t):
    ca, cb = gt.PALETTES["guild"]["bg"], gt.PALETTES["guild"]["bg"]
    ca, cb = fn.dark.hexc(a), fn.dark.hexc(b)
    return "#%02X%02X%02X" % tuple(round(ca[i] * (1 - t) + cb[i] * t) for i in range(3))


def callout(d, x, y, n, text, accent):
    d.ellipse([x, y, x + 22, y + 22], fill=accent)
    T(d, x + 11, y + 11, str(n), F(HIRA, 12, 2), "#0E1512", anchor="mm")
    T(d, x + 32, y + 4, text, F(HIRA, 13), P["text"])


def sheet(title, sub, scene, steps, result, win, out, accent, key):
    W, H = 1840, 700
    img, d = gt.page(W, H)
    T(d, 48, 34, title, F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, sub, F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 320, 46, W - 48, 90], radius=20, fill="#161C26", outline=accent)
    T(d, W - 184, 68, "场景演示 · 未实现", F(HIRA, 13), accent, anchor="mm")
    gt.paste_win(img, win, 48, 128, scale=0.62, radius=10, shadow=True)
    d.rounded_rectangle([48, 128, 48 + int(1300 * 0.62), 128 + int(800 * 0.62)],
                        radius=10, outline="#2A3648", width=1)
    # 右侧说明
    sx = 890
    d.rounded_rectangle([sx, 128, W - 48, 380], radius=14, fill="#111722", outline="#1F2937")
    T(d, sx + 22, 146, "什么时候用", F(HIRA, 13, 2), accent)
    T(d, sx + 22, 172, scene, F(HIRA, 13), P["text"])
    T(d, sx + 22, 214, "三步完成", F(HIRA, 13, 2), accent)
    yy = 240
    for i, s in enumerate(steps):
        d.ellipse([sx + 24, yy + 2, sx + 42, yy + 20], fill=accent)
        T(d, sx + 33, yy + 11, str(i + 1), F(HIRA, 11, 2), "#0E1512", anchor="mm")
        T(d, sx + 52, yy + 1, s, F(HIRA, 12), P["text"])
        yy += 30
    T(d, sx + 22, 336, "得到什么", F(HIRA, 13, 2), accent)
    T(d, sx + 22, 362, result, F(HIRA, 12), MD["h2"])
    # 关键说明
    d.rounded_rectangle([sx, 400, W - 48, 640], radius=14, fill="#111722", outline="#1F2937")
    T(d, sx + 22, 418, "这包里有什么", F(HIRA, 13, 2), accent)
    for i, line in enumerate(PACK_LINES[key]):
        T(d, sx + 22, 446 + i * 26, "· " + line, F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 596, "需要 app 改动：" + NEED[key], F(HIRA, 12), "#93A3BE")
    img.save(out)
    print(out)


PACK_LINES = {
    "assets": ["资源目录约定（source/img、source/pdf…）与命名规范",
               "拖入/粘贴即自动入库：按「日期-描述」重命名，重名自动加序号",
               "插入时写短引用（img/xxx.png），不用记长路径",
               "素材库面板：搜索、预览、复用、缺失引用检查"],
    "cards": ["卡片墙视图（封面图 + 摘要 + 日期 + 目录色）",
              "排序与筛选：最近编辑 / 按目录 / 带图 / 未完成",
              "卡片样式跟随当前主题（颜色、字体、圆角、留白）"],
    "reader": ["阅读模式（隐藏侧栏与工具，只留正文）",
               "浮动大纲：章节跳转，读长文不迷路",
               "字号/行距/栏宽三档预设，跟随主题排版规则"],
    "health": ["文档体检规则集（层级跳跃 / 超长段落 / 缺图注 / 表格列不齐 / 死链 / 空章节）",
               "问题面板：严重级别 + 行号 + 一键跳转",
               "编辑器内标记：轻微下划线，不遮字、不打断输入"],
}

NEED = {
    "assets": "需要文件重命名/移动 + 面板（都是本地操作）",
    "cards": "需要新视图（读目录索引，几乎不动数据层）",
    "reader": "需要视图切换与排版预设",
    "health": "需要解析器 + 面板（可复用现有 Markdown tokenizer）",
}


def base_window():
    return review.render_window(P).copy()


def scenario_assets():
    win = base_window()
    d = ImageDraw.Draw(win)
    # 右侧素材库面板（替换预览区）
    d.rectangle([820, 0, 1300, 800], fill=P["bg"])
    d.line([(820, 0), (820, 800)], fill=P["line"])
    T(d, 846, 16, "素材库 · source/img", F(HIRA, 15, 2), P["text"])
    T(d, 846, 42, "共 128 张 · 3 张未被任何笔记引用", F(HIRA, 11), P["--text-secondary"])
    d.rounded_rectangle([846, 64, 1274, 96], radius=9, fill=P["card"], outline=P["line"])
    T(d, 860, 72, "搜索素材（文件名 / 尺寸 / 引用它的笔记）", F(HIRA, 11), P["--text-secondary"])
    names = ["09-12-方案图", "09-11-手绘线稿", "09-10-截图-账目", "09-08-配色稿", "09-05-流程图", "09-03-封面"]
    for i, n in enumerate(names):
        col, row = i % 3, i // 3
        x, y = 846 + col * 146, 112 + row * 150
        d.rounded_rectangle([x, y, x + 132, y + 96], radius=8,
                            fill=mix(P["bg"], MD["h2"], 0.22), outline=P["line"])
        d.rectangle([x + 10, y + 62, x + 122, y + 86], fill=mix(P["bg"], P["text"], 0.06))
        T(d, x + 10, y + 66, n, F(HIRA, 10), P["text"])
        if i == 2:
            d.rounded_rectangle([x, y, x + 132, y + 96], radius=8, outline=MD["h1"], width=2)
    d.rounded_rectangle([846, 424, 1274, 500], radius=10, fill=P["card"], outline=P["line"])
    T(d, 862, 436, "这张图被 3 篇笔记引用", F(HIRA, 12), P["text"])
    T(d, 862, 460, "「账目」产品设计文档 v1.0.md　·　周记 09.md　·　收件箱", F(HIRA, 11), MD["h2"])
    T(d, 862, 480, "删除前会提示引用位置", F(HIRA, 11), P["--text-secondary"])
    # 编辑器里的插入结果
    # 编辑区空白处的「刚插入」示例与提示（不压正文）
    T_mix(d, 360, 426, "![方案图](img/09-12-方案图.png)", F(MONO, 13), F(HIRA, 13), MD["h1"])
    T(d, 360, 454, "↑ 自动写短引用：不用记长路径，也不用管目录结构", F(HIRA, 11), P["--text-secondary"])
    d.rounded_rectangle([346, 490, 800, 538], radius=10, fill=mix(P["bg"], MD["h1"], 0.16), outline=MD["h1"])
    T(d, 362, 502, "已存入 source/img/09-12-方案图.png", F(HIRA, 12), MD["h1"])
    T(d, 362, 520, "自动命名「日期-描述」，重名自动加序号（本地完成）", F(HIRA, 10), P["--text-secondary"])
    return win


def scenario_cards():
    win = base_window()
    d = ImageDraw.Draw(win)
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 16, "卡片墙", F(HIRA, 17, 2), P["text"])
    T(d, 358, 44, "最近编辑 · 12 篇", F(HIRA, 11), P["--text-secondary"])
    tabs = ["最近编辑", "按目录", "带图", "未完成"]
    for i, t in enumerate(tabs):
        x = 520 + i * 92
        d.rounded_rectangle([x, 16, x + 80, 42], radius=9,
                            fill=P["card"] if i == 0 else None, outline=None if i == 0 else P["line"])
        T(d, x + 40, 29, t, F(HIRA, 11), P["text"] if i == 0 else P["--text-secondary"], anchor="mm")
    cards = [("《账目》产品设计文档", "09-12", "记账 app 的边界与验收标准…", MD["h1"]),
             ("周记 09", "09-11", "这周把主题系统做完了，深林夜…", MD["h2"]),
             ("markdown 有哪些语法", "09-10", "标题、粗体、列表、表格、公式…", MD["h3"]),
             ("秋分 · 阳台观察记", "09-08", "今天风很大，我把薄荷搬到窗边…", MD["bold"]),
             ("配色评审记录", "09-05", "青瓷灰 / 藕荷 / 沙金 三个方向…", MD["math"]),
             ("收件箱", "09-03", "待整理：剪藏片段 3 条", MD["insert"])]
    for i, (title, date, summary, color) in enumerate(cards):
        col, row = i % 3, i // 3
        x, y = 358 + col * 316, 74 + row * 330
        d.rounded_rectangle([x, y, x + 296, y + 306], radius=14, fill=P["card"], outline=P["line"])
        d.rounded_rectangle([x, y, x + 296, y + 132], radius=14, fill=mix(P["bg"], color, 0.30))
        T(d, x + 16, y + 96, date, F(HIRA, 11), P["text"])
        T(d, x + 16, y + 150, title, F(HIRA, 15, 2), P["text"])
        T(d, x + 16, y + 180, summary, F(HIRA, 12), P["--text-secondary"])
        d.rounded_rectangle([x + 16, y + 240, x + 90, y + 268], radius=9, outline=P["line"])
        T(d, x + 53, y + 254, "打开", F(HIRA, 11), color, anchor="mm")
        T(d, x + 16, y + 278, "1,240 字 · 3 张图", F(HIRA, 10), P["--text-secondary"])
    return win


def scenario_reader():
    win = base_window()
    d = ImageDraw.Draw(win)
    d.rectangle([0, 0, 1300, 800], fill=P["bg"])
    # 浮动退出按钮
    d.rounded_rectangle([24, 20, 148, 52], radius=10, fill=P["card"], outline=P["line"])
    T(d, 86, 36, "退出阅读 ⌘R", F(HIRA, 11), P["--text-secondary"], anchor="mm")
    # 正文单栏
    T(d, 250, 90, "《账目》产品设计文档", F(SONG, 30, 0), P["text"])
    T(d, 250, 138, "v1.0 · 2026-09-12 · 1,240 字", F(HIRA, 12), P["--text-secondary"])
    d.line([(250, 168), (1050, 168)], fill=P["line"])
    body = ["记账这件事的边界在哪：只做「记录」，不做「财务建议」。",
            "第一版先解决三件事：快速记一笔、看得到的分类、月底一眼看完。",
            "输入方式优先键盘：⌘N 新建、日期自动填、金额支持算式。"]
    yy = 196
    for line in body:
        T(d, 250, yy, line, F(HIRA, 16), P["text"])
        yy += 40
    T(d, 250, yy + 10, "一、为什么是「看」而不是「写」", F(SONG, 20, 1), MD["h1"])
    for line in ["我最近用钱太猛，需要看看钱花在哪。", "所以先做 macOS 版，再考虑 iOS。"]:
        yy += 46
        T(d, 250, yy, line, F(HIRA, 16), P["text"])
    # 浮动大纲
    d.rounded_rectangle([1080, 190, 1276, 470], radius=12, fill=P["card"], outline=P["line"])
    T(d, 1098, 206, "大纲", F(HIRA, 12, 2), P["text"])
    for i, (t, indent) in enumerate([("产品边界", 0), ("第一版三件事", 1), ("输入方式", 1),
                                     ("为什么是「看」", 0), ("先 macOS 后 iOS", 1)]):
        yy = 236 + i * 30
        if i == 3:
            d.rounded_rectangle([1090, yy - 4, 1266, yy + 22], radius=6, fill=mix(P["bg"], MD["h1"], 0.18))
        T(d, 1100 + indent * 14, yy, t, F(HIRA, 11), MD["h1"] if i == 3 else P["--text-secondary"])
    d.rounded_rectangle([1080, 490, 1276, 560], radius=12, fill=P["card"], outline=P["line"])
    T(d, 1098, 506, "阅读设置", F(HIRA, 12, 2), P["text"])
    for i, t in enumerate(["字号 中 · 行距 宽", "栏宽 760（舒适）", "跟随主题排版规则"]):
        T(d, 1098, 528 + i * 12, t, F(HIRA, 10), P["--text-secondary"])
    return win


def scenario_health():
    win = base_window()
    d = ImageDraw.Draw(win)
    d.rectangle([980, 0, 1300, 766], fill=P["bg"])
    d.line([(980, 0), (980, 766)], fill=P["line"])
    T(d, 1002, 16, "文档体检", F(HIRA, 15, 2), P["text"])
    T(d, 1002, 42, "6 项结果 · 2 项建议修改", F(HIRA, 11), P["--text-secondary"])
    issues = [("!", "标题层级跳跃", "H1 → H3（第 12 行）", MD["bold"]),
              ("!", "超长段落", "第 18 行 428 字，建议拆分", MD["italic"]),
              ("·", "图片缺图注", "img/09-12-方案图.png", MD["h2"]),
              ("·", "表格列数不齐", "第 34 行 3 列 / 2 列", MD["h2"]),
              ("·", "空章节", "「四、风险」没有内容", MD["h2"]),
              ("✓", "链接可访问", "5 个外链全部正常", MD["insert"])]
    for i, (mark, title, detail, color) in enumerate(issues):
        y = 70 + i * 86
        d.rounded_rectangle([1002, y, 1278, y + 74], radius=10, fill=P["card"], outline=P["line"])
        d.ellipse([1016, y + 12, 1038, y + 34], fill=mix(P["bg"], color, 0.35))
        T(d, 1027, y + 23, mark, F(HIRA, 12, 2), color, anchor="mm")
        T(d, 1050, y + 12, title, F(HIRA, 13, 2), P["text"])
        T(d, 1016, y + 40, detail, F(HIRA, 11), P["--text-secondary"])
        if i < 2:
            d.rounded_rectangle([1180, y + 42, 1266, y + 66], radius=8, outline=color)
            T(d, 1223, y + 54, "定位", F(HIRA, 11), color, anchor="mm")
    # 编辑器内标记（第 12/18 行的下划线）
    T_mix(d, 360, 296, "### 验收标准", F(MONO, 13), F(HIRA, 13), MD["h3"])
    d.line([(360, 322), (540, 322)], fill=MD["bold"], width=2)
    T_mix(d, 360, 334, "这一段写得非常长，把产品目标、边界、验收、埋点全塞在一起……", F(MONO, 12), F(HIRA, 12), P["text"])
    d.line([(360, 362), (900, 362)], fill=MD["italic"], width=2)
    return win


def main():
    outdir = ROOT / "docs/proposals/plugins"
    outdir.mkdir(parents=True, exist_ok=True)
    sheet("场景演示 ① · 素材库（图片与附件）",
          "直接对应你之前提的问题：「绝对路径特别长」「得先把图导入 source/img」——这包把这一步自动化。",
          "从桌面拖一张截图进笔记，或直接 ⌘V 粘贴图片。",
          ["拖入 / 粘贴图片", "自动进 source/img 并按「日期-描述」命名", "插入短引用，之后在素材库里搜索复用"],
          "不再记路径、不再手动建目录；图片有没有被引用、有没有丢，一眼看得到。",
          scenario_assets(), outdir / "scenario-assets.png", MD["h1"], "assets")
    sheet("场景演示 ② · 卡片墙（另一种看库的方式）",
          "文件树适合「找」，不适合「回顾」。卡片墙把库摊开给你看——封面、摘要、日期、目录色。",
          "想找一篇印象里「写过但记不清标题」的旧笔记。",
          ["点顶部「卡片墙」", "按最近编辑 / 带图 / 未完成筛选", "点卡片直接打开"],
          "标题想不起来也能凭画面找回来；卡片颜色跟随当前主题。",
          scenario_cards(), outdir / "scenario-cards.png", MD["h2"], "cards")
    sheet("场景演示 ③ · 阅读模式（一键进入沉浸）",
          "写完的产品文档、长笔记，自己回头读时不想看见文件树和工具按钮。",
          "想安安静静把一篇 3000 字的长文从头读完。",
          ["⌘R 进入阅读模式", "用浮动大纲跳章节", "再按 ⌘R 回到编辑"],
          "同一篇文档，变成「能读」的样子：单栏、大字、留白，排版跟随主题规则。",
          scenario_reader(), outdir / "scenario-reader.png", MD["h3"], "reader")
    sheet("场景演示 ④ · 文档体检（打开就告诉你哪里该改）",
          "不是逐字纠错（那是校对），而是「这篇文档作为文档，还差什么」。",
          "一篇产品文档写完，准备发给别人之前。",
          ["打开文档自动体检", "看右侧问题列表（带行号）", "点「定位」跳到那一段"],
          "发出去之前把结构问题清掉：层级、超长段落、缺图注、表格列数、空章节、死链。",
          scenario_health(), outdir / "scenario-health.png", MD["bold"], "health")


if __name__ == "__main__":
    main()
