#!/usr/bin/env python3
"""模板插件方案对照图：日记 / 待办 / 课堂笔记，各 3 套方案。

用法：python3 scripts/make-template-proposals.py [输出路径]
输出：docs/proposals/templates-preview.png
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/templates-preview.png"

HEI = "/System/Library/Fonts/STHeiti Medium.ttc"
HEI_L = "/System/Library/Fonts/STHeiti Light.ttc"
SONG = "/System/Library/Fonts/Supplemental/Songti.ttc"

TEAL = (46, 125, 114)
TEAL_SOFT = (228, 240, 237)
INK = (31, 35, 40)
GRAY = (92, 101, 112)
GRAY_L = (150, 158, 168)
LINE = (227, 222, 214)
PAPER = (251, 249, 246)
CINNABAR = (192, 86, 60)

W, H = 1500, 1360
SCALE = 2


def font(path, size):
    return ImageFont.truetype(path, size * SCALE, index=0)


F_TITLE = font(HEI, 26)
F_H2 = font(HEI, 17)
F_H3 = font(HEI, 14)
F_BODY = font(SONG, 12)
F_SMALL = font(SONG, 10.5)
F_MONO = font(SONG, 10.5)


def rounded(d, box, r, fill=None, outline=None, width=1):
    d.rounded_rectangle([c * SCALE for c in box], radius=r * SCALE,
                        fill=fill, outline=outline, width=width * SCALE)


def text(d, xy, s, f, fill=INK, anchor="la"):
    d.text((xy[0] * SCALE, xy[1] * SCALE), s, font=f, fill=fill, anchor=anchor)


TEMPLATES = [
    {
        "name": "日记",
        "tag": "模板 · journal",
        "plans": [
            ("A. 极简三行", ["今天：", "心情：（晴 / 阴 / 雨，选一个）", "一件小事："],
             ["# 2026-09-19 周六", "今天：", "心情：", "一件小事：", "",
              "> 写不出就跳过，不留空格强迫症"], "最省事：30 秒能写完"),
            ("B. 结构化日记（推荐）",
             ["天气 / 心情标签", "三件好事 · 一件难事", "今日复盘 + 明日一件事", "自动带入日期与星期"],
             ["# 2026-09-19 周六（晴）", "## 三件好事", "1. ", "2. ", "3. ", "## 今日复盘", "- 做成了：",
              "- 卡住了：", "## 明天只做一件事", "- "], "自带周/月汇总视图（按心情或标签筛）"),
            ("C. 时间轴日记", ["按时间段记事件流", "适合碎片式记录", "可插入照片与语音备注"],
             ["# 2026-09-19", "- 08:20 起床，跑步 3km", "- 10:00 图书馆（拍了照）",
              "- 14:30 组会：讲了进度", "- 23:00 收尾"], "回看时按时间线呈现"),
        ],
    },
    {
        "name": "待办",
        "tag": "模板 · todo",
        "plans": [
            ("A. 单页清单",
             ["今天 / 本周 / 以后 三段", "勾选即完成（卡片墙进度徽章）", "完成项不删，留痕"],
             ["# 待办 2026-09-19", "## 今天", "- [ ] 交实验报告", "- [ ] 给导师回邮件",
              "## 本周", "- [ ] 复习线代第 4 章", "## 以后", "- [ ] 整理照片库"],
             "配合卡片墙「待办筛选」一眼看到没做完的"),
            ("B. 看板式（推荐）",
             ["三列：待办 / 进行中 / 已完成", "每条带 @谁 · 截止日 · #标签", "拖拽换列（预览内拖不动，编辑器里改标记）"],
             ["# 看板 2026-W38", "## 待办", "- [ ] 文献综述 @我 ⏰09-22 #论文",
              "## 进行中", "- [ ] 实验数据整理 @我 ⏰09-20 #实验",
              "## 已完成", "- [x] 开题报告提纲 #论文"], "适合多人协作或一周节奏"),
            ("C. 周期待办（结转）",
             ["每日 / 每周模板", "未完成自动结转到下一天", "带「连续坚持」天数"],
             ["# 每日 2026-09-19", "- [ ] 背 50 个单词（连续 12 天）", "- [ ] 运动 30 分钟",
              "- [x] 阅读 20 页", "", "> 昨天没做完的 2 条已转到今天"],
             "需要一点自动化：模板声明「结转未完成」"),
        ],
    },
    {
        "name": "课堂笔记",
        "tag": "模板 · class",
        "plans": [
            ("A. 康奈尔笔记（推荐）",
             ["线索 / 笔记 / 总结 三段", "课后 5 分钟写总结", "复习时遮住右栏自测"],
             ["# 线代 · 第 4 讲 特征值", "## 线索（关键词）", "- 特征多项式", "- 相似对角化",
              "## 笔记", "- 定义：det(A-λI)=0 …", "- 例题：3×3 求特征值 …",
              "## 总结", "- 一句话：先求 λ，再求特征向量"], "经典、好复习"),
            ("B. 课前 / 课中 / 课后",
             ["课前：问题清单", "课中：要点 + 板书照片位", "课后：疑问与答案 + 参考资料"],
             ["# 数据结构 · 第 6 讲 树", "## 课前问题", "1. 为什么用 B 树？",
              "## 课中要点", "- 二叉树遍历：前/中/后", "- ![板书](img/板书.jpg)",
              "## 课后疑问", "- [ ] 红黑树旋转还是没懂", "## 参考", "- 教材 §6.3"], "把「不懂」变成可追踪的待办"),
            ("C. 理工科实验/公式版",
             ["公式区（KaTeX）", "例题与步骤分栏", "实验数据表 + 误差分析"],
             ["# 物理实验 · 单摆测 g", "## 公式", "$$T = 2\\pi\\sqrt{L/g}$$",
              "## 数据", "| 次数 | L(m) | T(s) |", "| --- | --- | --- |", "| 1 | 0.80 | 1.79 |",
              "## 误差分析", "- 主要来自计时反应时间"], "带公式与数据表，预览可直接渲染"),
        ],
    },
]


def draw_card(d, x, y, w, h, title, bullets, sample, note, highlight=False):
    rounded(d, (x, y, x + w, y + h), 10, fill=PAPER, outline=TEAL if highlight else LINE,
            width=2 if highlight else 1)
    d.rectangle([(x + 1) * SCALE, y * SCALE, (x + 5) * SCALE, (y + h) * SCALE],
                fill=TEAL if highlight else GRAY_L)
    text(d, (x + 16, y + 12), title, F_H3, TEAL if highlight else INK)
    ty = y + 38
    for b in bullets:
        text(d, (x + 16, ty), "· " + b, F_SMALL, GRAY)
        ty += 17
    # mini 样例（当作笔记预览）
    rounded(d, (x + 16, ty + 4, x + w - 16, y + h - 34), 6, fill=(255, 255, 255), outline=LINE)
    sy = ty + 14
    for line in sample[:7]:
        text(d, (x + 24, sy), line[:34], F_MONO, INK if line.startswith("#") else GRAY)
        sy += 14
    text(d, (x + 16, y + h - 22), note, F_SMALL, CINNABAR)


def main():
    img = Image.new("RGB", (W * SCALE, H * SCALE), (255, 255, 255))
    d = ImageDraw.Draw(img)
    text(d, (40, 30), "模板插件 · 方案对照（3 个模板 × 每个 3 套方案）", F_TITLE, TEAL)
    text(d, (40, 70), "标「推荐」的是我的建议；每套都可以混搭（比如日记用 B 的结构 + A 的极简写法）。"
                      "审核通过后我再开工。", F_BODY, GRAY)
    text(d, (40, 92), "落盘格式：普通 Markdown（变量在新建时替换）+ 模板包里声明分类、图标、默认文件名规则。",
         F_BODY, GRAY_L)

    y = 130
    for t in TEMPLATES:
        rounded(d, (40, y, W - 40, y + 32), 6, fill=TEAL_SOFT)
        text(d, (52, y + 8), f"{t['name']}", F_H2, TEAL)
        # 标签跟在标题后面：按标题实际宽度定位，避免和标题重叠
        title_w = d.textlength(t["name"], font=F_H2) / SCALE
        text(d, (52 + title_w + 12, y + 12), t["tag"], F_SMALL, GRAY)
        y += 44
        cw = (W - 80 - 2 * 18) / 3
        for i, (title, bullets, sample, note) in enumerate(t["plans"]):
            draw_card(d, 40 + i * (cw + 18), y, cw, 300, title, bullets, sample, note,
                      highlight=("推荐" in title))
        y += 320
    text(d, (40, H - 40), "待你确认：① 插件层级（声明式 / 带渲染增强 / 带自动化） "
                          "② 每个模板选哪套 ③ 变量范围 ④ 新建入口与命名规则", F_BODY, GRAY)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img = img.resize((W, H), Image.LANCZOS)
    img.save(OUT)
    print("已生成：", OUT)


if __name__ == "__main__":
    main()
