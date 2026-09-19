#!/usr/bin/env python3
"""方案 D（结构化块）评审图：三层结构 + before/after + 兼容性 + 分期。

用法：python3 scripts/make-template-block-proposals.py [输出路径]
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/templates-block-D.png"

HEI = "/System/Library/Fonts/STHeiti Medium.ttc"
SONG = "/System/Library/Fonts/Supplemental/Songti.ttc"
MENLO = "/System/Library/Fonts/Menlo.ttc"

TEAL = (46, 125, 114)
TEAL_D = (31, 90, 82)
TEAL_SOFT = (228, 240, 237)
INK = (31, 35, 40)
GRAY = (92, 101, 112)
GRAY_L = (150, 158, 168)
LINE = (227, 222, 214)
PAPER = (251, 249, 246)
CINNABAR = (192, 86, 60)
GOLD = (176, 148, 90)

W, H = 1560, 840
SCALE = 2


def font(path, size):
    return ImageFont.truetype(path, int(size * SCALE), index=0)


F_TITLE = font(HEI, 25)
F_H2 = font(HEI, 16)
F_H3 = font(HEI, 13)
F_BODY = font(SONG, 11.5)
F_SMALL = font(SONG, 10)
# 示例行里既有代码又有中文：Menlo 没有中文字形（会变方框），统一用宋体
F_MONO = font(SONG, 10.5)
F_MONO_S = font(SONG, 9.5)


def box(d, x, y, w, h, fill=PAPER, outline=LINE, r=9, width=1):
    d.rounded_rectangle([x * SCALE, y * SCALE, (x + w) * SCALE, (y + h) * SCALE],
                        radius=r * SCALE, fill=fill, outline=outline, width=width * SCALE)


def text(d, x, y, s, f, fill=INK, anchor="la"):
    d.text((x * SCALE, y * SCALE), s, font=f, fill=fill, anchor=anchor)


def lines(d, x, y, items, f=F_MONO, fill=GRAY, step=13, limit=44):
    for i, s in enumerate(items):
        text(d, x, y + i * step, s[:limit], f, fill if not s.startswith("#") else INK)


def main():
    img = Image.new("RGB", (W * SCALE, H * SCALE), (255, 255, 255))
    d = ImageDraw.Draw(img)
    text(d, 40, 28, "方案 D · 结构化块：模板插入后「不用手改」", F_TITLE, TEAL)
    text(d, 40, 64, "原则不变：文件仍是普通 Markdown（VS Code / GitHub 打开照样能读）；结构化只是「我们这一层多给了控件」。",
         F_BODY, GRAY)
    text(d, 40, 84, "D1 元数据卡（YAML front matter） · D2 行内控件（勾选/日期/标签/进度） · D3 块容器（康奈尔、实验数据） · "
                    "D4 全控件化（不做，会破坏「文件即笔记」）",
         F_SMALL, GRAY_L)

    # ── 三层结构 ──
    y = 116
    box(d, 40, y, W - 80, 168, fill=(255, 255, 255))
    text(d, 56, y + 12, "① 三层结构：一层管元数据，一层管行内，一层管成块结构", F_H2, TEAL_D)
    cw = (W - 80 - 32 - 2 * 14) / 3
    layers = [
        ("D1 元数据卡（笔记头部）", "日记/课堂笔记的固定字段，用控件改，不碰 YAML",
         ["---", "type: 日记", "date: 2026-09-19", "weather: 晴", "mood: 🙂", "tags: [日记]", "---"]),
        ("D2 行内控件（正文里）", "勾选、截止日、标签、进度：语法兼容 Markdown 生态",
         ["- [ ] 交实验报告", "      @due(2026-09-22) #论文", "- [x] 开题提纲 #论文", "",
          "进度 :: 3/8", "心情 :: 🙂"]),
        ("D3 块容器（成块结构）", "康奈尔三栏、实验数据：与现有 ::: 语法同源",
         ["::: cornell 线代·第4讲", "线索 :: 特征多项式", "笔记 :: det(A-λI)=0", "总结 :: 先求 λ",
          ":::", "", "::: data 单摆测 g"]),
    ]
    for i, (title, desc, sample) in enumerate(layers):
        x = 56 + i * (cw + 14)
        box(d, x, y + 38, cw, 118, fill=PAPER)
        text(d, x + 12, y + 48, title, F_H3, TEAL_D)
        text(d, x + 12, y + 68, desc[:38], F_SMALL, GRAY)
        lines(d, x + 12, y + 86, sample, F_MONO_S, step=11)
    y += 182

    # ── before / after ──
    text(d, 40, y, "② 效果对照：同一份文件，插入时的样子（左）vs D 方案下的样子（右）", F_H2, TEAL_D)
    y += 26
    cases = [
        ("日记", ["# 2026-09-19 周六", "天气：", "心情：", "今天：", "三件好事：", "1. ", "2. "],
         ["【属性卡】日期 2026-09-19 · 周六", "【下拉】天气 晴   【标签】心情 🙂", "【正文】今天：<光标直接在这里>",
          "【控件】三件好事 1. 2. 3. 每行左侧有勾选"]),
        ("待办", ["- [ ] 事项一", "- [ ] 事项二", "（没有日期/标签）"],
         ["【勾选框】交实验报告", "【日期控件】截止 09-22（点一下改）", "【标签】#论文",
          "【进度条】3/8（自动统计勾选项）"]),
        ("课堂笔记", ["线索：", "笔记：", "总结：", "（三栏要手写）"],
         ["【三栏块】线索 / 笔记 / 总结 各自成栏", "【公式】KaTeX 直接渲染", "【数据表】行列可增删",
          "【勾选疑问】把「没听懂」变待办"]),
    ]
    cw2 = (W - 80 - 2 * 16) / 3
    for i, (name, before, after) in enumerate(cases):
        x = 40 + i * (cw2 + 16)
        box(d, x, y, cw2, 236, fill=(255, 255, 255))
        text(d, x + 12, y + 10, name, F_H3, INK)
        text(d, x + 12, y + 32, "现在（纯文本插入）", F_SMALL, CINNABAR)
        lines(d, x + 12, y + 50, before, F_MONO_S, step=12, limit=36)
        d.line([(x + 12) * SCALE, (y + 148) * SCALE, (x + cw2 - 12) * SCALE, (y + 148) * SCALE],
               fill=LINE, width=SCALE)
        text(d, x + 12, y + 156, "D 方案（控件 + 渲染）", F_SMALL, TEAL)
        lines(d, x + 12, y + 174, after, F_MONO_S, step=13, limit=36)
    y += 252

    # ── 兼容性与分期 ──
    left_w = (W - 80 - 18) * 0.52
    box(d, 40, y, left_w, 196, fill=(255, 255, 255))
    text(d, 56, y + 12, "③ 兼容性：同一份 .md 在别处长什么样", F_H2, TEAL_D)
    text(d, 56, y + 38, "别处打开（VS Code / GitHub / 手机）：", F_SMALL, GRAY)
    lines(d, 56, y + 56, ["---", "type: 日记", "date: 2026-09-19", "mood: 🙂", "---", "",
                          "- [ ] 交实验报告 @due(2026-09-22) #论文", "::: cornell 线代·第4讲",
                          "线索 :: 特征多项式"], F_MONO_S, step=12)
    text(d, 56, y + 168, "→ front matter 与 check box 是通用写法；::: 块退化成普通围栏文本，仍可读。",
         F_SMALL, GRAY)

    box(d, 40 + left_w + 18, y, W - 80 - left_w - 18, 196, fill=TEAL_SOFT)
    text(d, 40 + left_w + 34, y + 12, "④ 分期（每期都先给四主题对照图再开工）", F_H2, TEAL_D)
    stages = [
        ("阶段 1", "元数据卡 D1 + 行内日期/标签 D2（只读识别 + 点击改）", "日记模板即可用"),
        ("阶段 2", "待办行控件 + 进度统计 + 看板式预览", "待办模板即可用"),
        ("阶段 3", "块容器 D3（康奈尔三栏、实验数据表）", "课堂笔记即可用"),
        ("不做", "D4 全控件化（笔记变数据库）", "会破坏「文件即笔记」，明确排除"),
    ]
    for i, (k, v, note) in enumerate(stages):
        yy = y + 40 + i * 38
        text(d, 40 + left_w + 34, yy, k, F_H3, TEAL_D)
        text(d, 40 + left_w + 76, yy + 2, v[:44], F_SMALL, INK)
        text(d, 40 + left_w + 76, yy + 18, note, F_SMALL, GRAY_L)

    text(d, 40, H - 42, "待你审核：① D1/D2/D3 三层都做，还是先只做 D1+D2？ "
                        "② 行内语法用 @due() / #tag（Obsidian Tasks 同款）还是别的？ "
                        "③ 康奈尔块用 ::: cornell 容器还是三列表格？ ④ 分期顺序是否认可", F_BODY, GRAY)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.resize((W, H), Image.LANCZOS).save(OUT)
    print("已生成：", OUT)


if __name__ == "__main__":
    main()
