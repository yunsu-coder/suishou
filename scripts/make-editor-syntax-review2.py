#!/usr/bin/env python3
"""编辑器语法配色评审稿 v2：线上现状 vs 新方案（主题必填 --md-* + 量化区分度）。

用法: python3 scripts/make-editor-syntax-review2.py [输出.png]
"""

import importlib.util
import math
import re
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
SONG, HIRA = gt.SONG, gt.HIRA
MONO = str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
MONO_B = str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")


# ── 新方案：每个主题的编辑器语法色（--md-*）──────────────────────────
MD = {
    "theme-misty-teal": dict(
        h1="#0B6B59", h2="#1668B0", h3="#5A3FC0", bold="#C43A4E", italic="#A63A8E", code="#8A6A0A",
        link="#0A6E92", quote="#5F6E67", math="#8A4A12", highlight="#B4551E", strike="#9A4A55",
        insert="#0E7A4A", callout="#9A6A0A", marker="#8A948D", table="#6E7A73", hr="#B9C6BE",
        url="#8A948D", fence="#7A8780"),
    "theme-sumi-paper": dict(
        h1="#B33A20", h2="#2F5FB0", h3="#6A3AA8", bold="#8A3E7A", italic="#0F6B57", code="#8A6A1E",
        link="#1F6E8A", quote="#5F5A50", math="#7A4A2E", highlight="#9A4A00", strike="#9A5A5A",
        insert="#2F7A4F", callout="#8A6A1E", marker="#8A8175", table="#6B6257", hr="#D8C9AE",
        url="#8A8175", fence="#7A6A70"),
    "theme-bubble-pop": dict(
        h1="#D6197F", h2="#6E35FF", h3="#0089A0", bold="#C4264C", italic="#B0561E", code="#8A6A0A",
        link="#1A66C4", quote="#6E5E80", math="#8A4A12", highlight="#A8262E", strike="#9A5A6A",
        insert="#00996B", callout="#96660A", marker="#9C8FAA", table="#7A6A8A", hr="#E6D2E8",
        url="#9C8FAA", fence="#8A7A90"),
}

# 线上现状：写死的系统色
BEFORE = dict(h1="#6B4FD9", h2="#6B4FD9", h3="#6B4FD9", bold="#FF9500", italic="#00A0A0",
              code="#FF9500", link="#007AFF", quote="#9A9A9A", math="#FF2D55", highlight="#FF3B30",
              strike="#9A9A9A", insert="#34C759", callout="#9A9A9A", marker="#9A9A9A",
              table="#9A9A9A", hr="#9A9A9A", url="#AF52DE", fence="#FF9500",
              text="#25302B", code_bg=None, hl_bg=None, text2="#9A9A9A")

CONTENT = ["h1", "h2", "h3", "bold", "italic", "code", "link", "quote", "math", "highlight", "strike", "insert"]
CORE = ["h1", "h2", "h3", "bold", "italic", "code"]
MARKERS = ["marker", "url", "hr", "table", "fence"]


def hexc(v):
    v = v.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3,8})", v)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
    m = re.fullmatch(r"rgba?\(([^)]*)\)", v)
    p = [x.strip() for x in m.group(1).split(",")]
    a = float(p[3]) if len(p) > 3 else 1.0
    base = (255, 255, 255)
    return tuple(round(int(p[i]) * a + base[i] * (1 - a)) for i in range(3))


def lab(h):
    r, g, b = [c / 255 for c in hexc(h)]
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = f(r), f(g), f(b)
    X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    g2 = lambda t: t ** (1 / 3) if t > 0.008856 else (7.787 * t + 16 / 116)
    fx, fy, fz = g2(X), g2(Y), g2(Z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def de(a, b):
    la, lb = lab(a), lab(b)
    return math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))


def chroma(h):
    _, a, b = lab(h)
    return math.hypot(a, b)


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in hexc(c)]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def over(fg, alpha, bg):
    c, b = hexc(fg), hexc(bg)
    return "#%02X%02X%02X" % tuple(round(c[i] * alpha + b[i] * (1 - alpha)) for i in range(3))


def draw_run(d, x, y, runs, size=13):
    for r in runs:
        w = None
        if r.get("bg"):
            w = T_mix(d, x, y, r["text"], F(MONO, size), F(HIRA, size), r["color"])
            d.rounded_rectangle([x - 3, y - 2, w + 3, y + size + 7], radius=4, fill=r["bg"])
        f_lat = F(MONO_B, size)
        f_cjk = F(HIRA, size, 2 if r.get("bold") else 0)
        end = T_mix(d, x, y, r["text"], f_lat, f_cjk, r["color"])
        if r.get("strike"):
            d.line([(x, y + size * 0.66), (end, y + size * 0.66)], fill=r["color"], width=2)
        if r.get("underline"):
            d.line([(x, y + size + 5), (end, y + size + 5)], fill=r["color"], width=2)
        if r.get("italic"):
            pass
        x = end
    return x


def s(text, color, **kw):
    d = dict(text=text, color=color)
    d.update(kw)
    return d


def lines_for(c, bg, code_bg, hl_bg, mode):
    body = c.get("text", "#25302B")
    marker = c["marker"]
    hl_bg_col = hl_bg if mode == "after" else over("#FF3B30", 0.16, bg)
    code_bg_col = code_bg if mode == "after" else over("#FF9500", 0.12, bg)
    out = []
    out.append([s("#", marker, bold=True), s(" 一级标题", c["h1"], bold=True)])
    out.append([s("##", marker, bold=True), s(" 二级标题", c["h2"], bold=True)])
    out.append([s("###", marker, bold=True), s(" 三级标题", c["h3"], bold=True)])
    out.append([s("**", marker), s("粗体文字", c["bold"], bold=True), s("**", marker),
                s("　*", marker), s("斜体文字", c["italic"], italic=True), s("*", marker)])
    out.append([s("行内 ", body), s("`let x = 1`", c["code"], bg=code_bg_col),
                s("　链接 ", body), s("[文档](https://a.b)", c["link"], underline=True)])
    out.append([s("![", marker), s("图片", c["link"], underline=True), s("](", marker),
                s("source/img/a.png", c["url"]), s(")", marker)])
    out.append([s("> ", c["quote"]), s("引用：第七朵花开了", c["quote"])])
    out.append([s("- ", marker), s("列表项", body), s("　- [x] ", marker),
                s("已完成", c["insert"]), s("　- [ ] ", marker), s("待办", body)])
    out.append([s("1. ", marker), s("有序列表", body),
                s("　公式 ", body), s("$E=mc^2$", c["math"]), s("　脚注 ", body), s("[^1]", marker)])
    out.append([s("==", marker), s("高亮", c["highlight"], bg=hl_bg_col), s("==", marker),
                s("　~~", marker), s("删除线", c["strike"], strike=True), s("~~", marker),
                s("　++", marker), s("插入", c["insert"], underline=True), s("++", marker)])
    out.append([s("---", c["hr"]), s("　分隔线", c["quote"]),
                s("　| ", c["table"]), s("列 A", body), s(" |", c["table"])])
    out.append([s("| ", c["table"]), s("列 A", c["table_head"], bold=True),
                s(" | ", c["table"]), s("列 B", c["table_head"], bold=True), s(" |", c["table"])])
    out.append([s("| ", c["table"]), s("1", body), s(" | ", c["table"]), s("2", body),
                s(" |", c["table"]), s("　（表头加深、竖线中性）", c["quote"])])
    out.append([s("```", c["fence"]), s("swift", c["fence"], bold=True),
                s("　::: ", c["callout"]), s("tip", c["callout"], bold=True)])
    out.append([s("<div>", c["html"]), s(" HTML 标签", body), s("</div>", c["html"]),
                s("　[TOC]", c["marker"])])
    return out


def panel(img, d, x, y, w, h, title, sub, runs_list, bg, tone, border):
    d.rounded_rectangle([x, y, x + w, y + h], radius=12, fill=bg, outline=border)
    T(d, x + 16, y + 12, title, F(HIRA, 14, 2), tone)
    T(d, x + 16, y + 34, sub, F(HIRA, 11), "#8A948D")
    yy = y + 62
    for runs in runs_list:
        draw_run(d, x + 16, yy, runs)
        yy += 31


# 渲染器支持的语法 → 变量名 / 示例文本（编辑器必须都能看出来）
COVERAGE = [
    ("h1", "# 一级标题"), ("h2", "## 二级标题"), ("h3", "### 三级标题"),
    ("bold", "**粗体**"), ("italic", "*斜体*"), ("code", "`行内代码`"),
    ("link", "[链接](url)"), ("url", "(链接地址)"), ("embed", "![图片](a.png)"),
    ("kbd", "[[⌘S]]"), ("mention", "@同事"), ("emoji", ":smile:"),
    ("badge", "[badge:成功]"), ("timeline", "- [09-11] 内容"), ("term", "$ npm run"),
    ("math", "$E=mc^2$"), ("highlight", "==高亮=="), ("strike", "~~删除~~"),
    ("insert", "++插入++"), ("quote", "> 引用"), ("list", "- 列表"),
    ("number", "1. 有序"), ("task", "- [x] 任务"), ("hr", "--- 分隔线"),
    ("table", "| 列 A |"), ("table_head", "表头单元格"), ("fence", "```swift"),
    ("mermaid", "```mermaid"), ("callout", "::: tip"), ("html", "<div>"),
    ("marker", "[^1] 脚注"), ("marker", "[TOC]"), ("marker", "{#anchor}"),
    ("marker", "~下标~"), ("marker", "^上标^"),
]


def coverage_section(img, d, x, y, w, palettes):
    rows = len(COVERAGE)
    cols = 2
    per = (rows + cols - 1) // cols
    h = 74 + per * 30
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill="#111722", outline="#1F2937")
    T(d, x + 22, y + 16, f"语法覆盖清单（{rows} 项 · 渲染器支持什么，编辑器就有什么颜色）",
      F(HIRA, 15, 2), "#EFF4FF")
    T(d, x + 22, y + 42, "每一行：示例语法（用雾青渲染）＋ 三个主题各自的颜色块 —— 对照编辑器里的实际颜色确认是否生效。",
      F(HIRA, 11), "#8FA0BB")
    for i, (key, sample) in enumerate(COVERAGE):
        col, row = i // per, i % per
        cx = x + 22 + col * (w // cols)
        cy = y + 66 + row * 30
        color = palettes["theme-misty-teal"].get(key, "#666666")
        T_mix(d, cx, cy, sample, F(MONO, 12), F(HIRA, 12), color)
        T(d, cx + 150, cy, key, F(HIRA, 10), "#5F6E86")
        for j, pkg in enumerate(("theme-misty-teal", "theme-sumi-paper", "theme-bubble-pop")):
            c = palettes[pkg].get(key, "#666666")
            bx = cx + 250 + j * 30
            d.rounded_rectangle([bx, cy - 2, bx + 22, cy + 14], radius=5, fill=c, outline="#2A3648")
    return y + h


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/game/editor-syntax.png"
    themes = [("theme-misty-teal", "雾青（青瓷纸感）"), ("theme-sumi-paper", "墨纸（宣纸墨线）"),
              ("theme-bubble-pop", "Bubble Pop（像素糖果）")]
    W, H = 1840, 2820
    coverage = {}
    img, d = gt.page(W, H)
    T(d, 48, 34, "编辑器语法配色 · 评审稿 v2（规则化）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "左＝线上（写死系统色，与主题脱轨）；右＝新方案（主题必填 --md-* 语法色，按量化区分度卡）。粗体/斜体/下划线/删除线/底纹都按真实编辑器渲染。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 380, 46, W - 48, 90], radius=20, fill="#161C26", outline="#E0C080")
    T(d, W - 214, 68, "未动手 · 等你审核色板", F(HIRA, 13), "#E0C080", anchor="mm")

    for i, (pkg, name) in enumerate(themes):
        y = 130 + i * 660
        v = {}
        css = (ROOT / "plugins-market" / "_review" / f"{pkg}-v5" / "theme.css").read_text(encoding="utf-8")
        for m in re.finditer(r"(--[a-z0-9-]+)\s*:\s*([^;]+);", css):
            v.setdefault(m.group(1), m.group(2).strip())
        bg, code_bg = v["--bg"], v.get("--code-bg", "#F2F2F2")
        code_bg = "#%02X%02X%02X" % hexc(code_bg)[:3]
        hl_bg = "#%02X%02X%02X" % hexc(v.get("--warn-bg", "#F7F1D8"))[:3]
        after = {k[len("--md-"):]: val for k, val in v.items() if k.startswith("--md-")}
        after["table_head"] = after.get("table-head", after.get("table", "#666666"))
        after["html"] = after.get("html", after.get("fence", "#666666"))
        after["highlight_bg"] = "#%02X%02X%02X" % hexc(after.get("highlight-bg", "#F7F1D8"))[:3]
        after["code_bg"] = "#%02X%02X%02X" % hexc(after.get("code-bg", "#F2F2F2"))[:3]
        after["text"] = v["--text"]
        after["text2"] = v.get("--text-secondary", "#777")
        hl_bg = after["highlight_bg"]
        code_bg = after["code_bg"]
        before = dict(BEFORE); before["text"] = v["--text"]
        for key in ("table_head", "html"):
            before.setdefault(key, before["table"])

        d.rounded_rectangle([40, y, 1800, y + 636], radius=16, fill="#111722", outline="#1F2937")
        T(d, 70, y + 18, name, F(HIRA, 19, 2), "#EFF4FF")
        T(d, 70, y + 46, "线上：标题/粗体/代码/链接/列表大多是系统色，且粗体与行内代码同色、引用/分隔线/删除线同色",
          F(HIRA, 11), "#E0A0A0")
        panel(img, d, 70, y + 72, 800, 470, "线上现状", "系统色 · 与主题脱轨 · 多处同色",
              lines_for(before, bg, code_bg, hl_bg, "before"), bg, "#E0A0A0", "#2A3648")
        panel(img, d, 900, y + 72, 800, 470, "新方案：主题自带语法色", "标记中性 · 内容分色 · 结构强区分",
              lines_for(after, bg, code_bg, hl_bg, "after"), bg, "#7FD1A8", "#2A3648")

        core_min = min(de(after[a], after[b]) for i, a in enumerate(CORE) for b in CORE[i + 1:])
        cont_min = min(de(after[a], after[b]) for i, a in enumerate(CONTENT) for b in CONTENT[i + 1:])
        worst_c = min(contrast(after[k], bg) for k in CONTENT)
        chroma_max = max(chroma(after[k]) for k in MARKERS)
        T(d, 70, y + 556,
          f"量化区分度：主色最小 ΔE {core_min:.0f}（门槛 22）　内容色最小 ΔE {cont_min:.0f}（门槛 12）　"
          f"内容色最低对比 {worst_c:.2f}:1（门槛 4.5）　标记最大彩度 {chroma_max:.0f}（门槛 ≤30，保持安静）",
          F(HIRA, 12, 2), "#7FD1A8")
        coverage[pkg] = after

    used = coverage_section(img, d, 48, H - 900, 1744, coverage)

    d.rounded_rectangle([48, used + 16, 1792, used + 202], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, used + 32, "要加的主题规则（auditVersion 5）", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, used + 60, "① 必填：每个主题必须声明 33 个编辑器语法色 --md-*，覆盖渲染器支持的全部语法（见上方清单）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, used + 86, "② 对比度：内容色在纸底上 ≥4.5:1；标记色 ≥3.0:1。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, used + 112, "③ 区分度：6 个主色两两 ΔE ≥ 22；12 个内容色两两 ΔE ≥ 12（Lab 距离，审计直接算）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, used + 138, "④ 标记要安静：标记 / URL / 分隔线 / 表格线 / 围栏 / HTML 的彩度 ≤30 —— 结构可见但不跟内容抢色。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, used + 164, "⑤ 编辑器落地：不再用系统色，改读当前主题的 --md-*；无主题时回落现有配色。tokenizer 仍是单次线性扫描 + 后台执行，打字性能不变。",
      F(HIRA, 13), "#B9C6DC")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
