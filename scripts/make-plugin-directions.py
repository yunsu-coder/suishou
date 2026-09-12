#!/usr/bin/env python3
"""插件包方向提案图（与主题同一套流程：方向 → 硬门槛 → 人工审核）。

用法: python3 scripts/make-plugin-directions.py [输出.png]
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
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO

CARD_BG = "#111722"
CARD_LINE = "#1F2937"

DIRECTIONS = [
    dict(id="export", name="导出成套", en="EXPORT PRESETS", star=3, cost="中",
         pain="写好的东西发到公众号 / 知乎 / 语雀 / 飞书时排版全散，导出样式只有一个",
         pack=["导出样式（CSS + 模板 HTML，离线内置）",
               "平台规则：图片宽度 / 代码块 / 引用 / 外链脚注 / 字号",
               "一键「复制到剪贴板」，直接粘进编辑器"],
         need="需要 app 加一层导出样式注入（现在 ExportService 样式写死）",
         gate="离线可用、不引外链、亮/暗底都可读、图片宽度有明确策略"),
    dict(id="lint", name="写作校对包", en="WRITING LINT", star=3, cost="中高",
         pain="中英混排空格、全角半角、错别字、术语不统一、标题层级乱，全靠肉眼找",
         pack=["声明式规则集（正则 + 替换建议 + 严重级别）",
               "一键修复 / 忽略 / 全部修复",
               "编辑器里下划线标记 + 右侧问题列表"],
         need="需要 app 加检查引擎 + 问题面板（编辑器已有着色管线可复用）",
         gate="每条规则必须带正例/反例 + 修复建议，禁止会误伤的规则"),
    dict(id="lang", name="语言支持包", en="LANGUAGE PACKS", star=2, cost="中",
         pain=".tex/.org/.adoc/.typ/.csv 这些文件在随手打开就是一片白",
         pack=["语言定义：关键字 / 注释符 / 缩进 / 括号配对",
               "对应的语义图标（含文件类型分色）",
               "代码块高亮别名（```tex 也能高亮）"],
         need="需要 app 允许从插件加载高亮规则（现在规则内置在 CodeHighlighter）",
         gate="必须给注释符 + 缩进 + 关键字表 + 图标，缺一不进列表"),
    dict(id="stats", name="写作统计包", en="WRITING STATS", star=2, cost="低中",
         pain="写了多少、什么时候写、有没有坚持、哪篇拖最久——全靠感觉",
         pack=["统计维度声明（字数 / 天数 / 文件 / 目录 / 时间带）",
               "卡片布局（热力图 / 趋势 / 排行）",
               "目标设定（本周 5000 字之类）"],
         need="需要 app 加统计面板（数据全本地，不联网）",
         gate="统计口径必须在包里写明（字数按什么算），不许含糊"),
    dict(id="skeleton", name="文档骨架包", en="DOC SKELETONS", star=3, cost="低",
         pain="论文、剧本、字幕、公文、教案的结构每次都要手搭一遍",
         pack=["结构化骨架（标题层级 + 锚点 + 表格 + Callout + 脚注位）",
               "变量占位（标题 / 日期 / 作者 / 版本）",
               "插入即用，不生成废话内容"],
         need="几乎不需要新能力（现有片段机制升级为「骨架 + 变量」即可）",
         gate="骨架必须可直接渲染通过（不许出现坏语法），变量必须有默认值"),
    dict(id="expert", name="AI 专家包", en="AI EXPERTS", star=2, cost="低",
         pain="AI 面板缺针对中文写作场景的专家（公文润色 / 论文摘要 / 中英互译）",
         pack=["专家定义：角色 + 输出格式 + 边界 + 至少 2 个示例",
               "输入模板（引用当前文档 / 选中段落）",
               "与主题无关，纯数据"],
         need="不需要新能力（现有专家机制即可）",
         gate="提示词必须含角色/格式/边界，且不得出现「直接给出成品」这类越界指令"),
]


def card(d, x, y, w, h, item, index):
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill=CARD_BG, outline=CARD_LINE)
    # 序号 + 名称
    d.rounded_rectangle([x + 20, y + 20, x + 58, y + 58], radius=10, fill="#1B2434", outline="#2A3648")
    T(d, x + 39, y + 39, str(index), F(HIRA, 18, 2), "#7FD1C0", anchor="mm")
    T(d, x + 72, y + 20, item["name"], F(HIRA, 19, 2), "#EFF4FF")
    T(d, x + 72, y + 48, item["en"], F(MENLO, 10, 1), "#5F6E86")
    # 推荐星级 / 成本
    stars = "★" * item["star"] + "☆" * (3 - item["star"])
    T(d, x + w - 20, y + 22, stars, F(HIRA, 14), "#E8C15A", anchor="rt")
    T(d, x + w - 20, y + 48, f"成本 {item['cost']}", F(HIRA, 11), "#8FA0BB", anchor="rt")
    # 痛点
    T(d, x + 20, y + 76, "痛点", F(HIRA, 12, 2), "#E0A0A0")
    T(d, x + 66, y + 76, item["pain"], F(HIRA, 12), "#B9C6DC")
    # 包内容
    T(d, x + 20, y + 106, "包内容", F(HIRA, 12, 2), "#7FD1C0")
    for i, line in enumerate(item["pack"]):
        T(d, x + 66, y + 106 + i * 22, "· " + line, F(HIRA, 12), "#B9C6DC")
    yy = y + 106 + len(item["pack"]) * 22 + 10
    T(d, x + 20, yy, "app 改动", F(HIRA, 12, 2), "#8FB8FF")
    T(d, x + 66, yy, item["need"], F(HIRA, 12), "#B9C6DC")
    T(d, x + 20, yy + 28, "硬门槛", F(HIRA, 12, 2), "#E8C15A")
    T(d, x + 66, yy + 28, item["gate"], F(HIRA, 12), "#B9C6DC")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/plugins/plugin-directions.png"
    W, H = 1840, 1560
    img, d = gt.page(W, H)
    T(d, 48, 34, "插件包 · 六个方向（先定方向，再做包）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "与主题同一套流程：方向 → 硬门槛 → 你审核 → 封版安装。★ 是我的推荐度，成本含「需要给 app 加的新能力」。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline="#E8C15A")
    T(d, W - 189, 68, "等你选方向", F(HIRA, 13), "#E8C15A", anchor="mm")

    for i, item in enumerate(DIRECTIONS):
        col, row = i % 2, i // 2
        x = 48 + col * 892
        y = 130 + row * 468
        card(d, x, y, 860, 436, item, i + 1)

    d.rounded_rectangle([48, H - 178, 1792, H - 40], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 160, "我的建议顺序", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, H - 130, "① 导出成套：对「写完好发出去」这件事帮助最大，成本中等（要给 app 加导出样式注入）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 104, "② 文档骨架包 + AI 专家包：几乎不需要新能力，纯数据就能做，收益立刻可见——建议先做这两个练流程。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 78, "③ 写作校对包：价值高，但要新引擎 + 面板，工作量最大，适合放到后面。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 52, "语言支持包 / 写作统计包：偏垂直，等你确认需要再排。",
      F(HIRA, 13), "#8FA0BB")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
