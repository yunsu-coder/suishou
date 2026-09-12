#!/usr/bin/env python3
"""为三套主题生成 auditVersion 5 候选：追加 --md-* 编辑器语法色，并自检对比度 / 区分度。

规则（v5）：
  内容色 ≥4.5:1 且两两 ΔE ≥12；主色 6 个两两 ΔE ≥22；标记色 ≥3.0:1 且彩度 ≤30。
不达标的色相会按同色相自动加深，直到过线（不会换色相，保持主题气质）。

用法: python3 scripts/apply-md-palettes.py
"""

import importlib.util
import json
import math
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKET = ROOT / "plugins-market"

CORE = ["h1", "h2", "h3", "bold", "italic", "code"]
CONTENT = CORE + ["link", "quote", "math", "highlight", "strike", "insert"]
MARKERS = ["marker", "url", "hr", "table", "fence", "html"]
VISIBLE = ["list", "number", "task"]
SEMANTIC = ["callout", "table-head"]
SEMANTIC_EXTRA = ["embed", "kbd", "mention", "emoji", "badge", "timeline", "term", "mermaid"]
BACKGROUNDS = ["code-bg", "highlight-bg"]

DRAFTS = {
    "theme-misty-teal": dict(
        h1="#0B6B59", h2="#1668B0", h3="#5A3FC0", bold="#C43A4E", italic="#A63A8E", code="#8A6A0A",
        link="#0A6E92", quote="#5F6E67", math="#8A4A12", highlight="#B4551E", strike="#9A4A55",
        insert="#0E7A4A", marker="#8A948D", url="#8A948D", list="#128A6E", number="#1668B0",
        task="#0E7A4A", hr="#B9C6BE", table="#6E7A73", fence="#7A8780", html="#7A8780",
        callout="#9A6A0A", embed="#1F6E8A", kbd="#6A4FB0", mention="#8A3FA8", emoji="#6E7A73",
        badge="#8A5A12", timeline="#0F7E63", term="#2F7A3A", mermaid="#5A3FC0",
        **{"table-head": "#3C5A52"}),
    "theme-sumi-paper": dict(
        h1="#B33A20", h2="#2F5FB0", h3="#6A3AA8", bold="#8A3E7A", italic="#0F6B57", code="#8A6A1E",
        link="#1F6E8A", quote="#5F5A50", math="#7A4A2E", highlight="#9A4A00", strike="#9A5A5A",
        insert="#2F7A4F", marker="#8A8175", url="#8A8175", list="#B33A20", number="#2F5FB0",
        task="#2F7A4F", hr="#D8C9AE", table="#6B6257", fence="#7A6A70", html="#7A6A70",
        callout="#8A6A1E", embed="#1F6E8A", kbd="#6A3AA8", mention="#8A3E7A", emoji="#6B6257",
        badge="#8A5A12", timeline="#2F7A4F", term="#7A4A2E", mermaid="#3F6B4F",
        **{"table-head": "#4A443B"}),
    "theme-bubble-pop": dict(
        h1="#D6197F", h2="#6E35FF", h3="#0089A0", bold="#C4264C", italic="#B0561E", code="#8A6A0A",
        link="#1A66C4", quote="#6E5E80", math="#8A4A12", highlight="#A8262E", strike="#9A5A6A",
        insert="#00996B", marker="#9C8FAA", url="#9C8FAA", list="#D6197F", number="#6E35FF",
        task="#00996B", hr="#E6D2E8", table="#7A6A8A", fence="#8A7A90", html="#8A7A90",
        callout="#96660A", embed="#1A66C4", kbd="#7A3FA8", mention="#B01E96", emoji="#7A6A8A",
        badge="#8A4A12", timeline="#00897B", term="#2F7A3A", mermaid="#6E35FF",
        **{"table-head": "#4A3A5E"}),
}


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
    return tuple(round(int(p[i]) * a + 255 * (1 - a)) for i in range(3))


def hx(rgb):
    return "#%02X%02X%02X" % rgb


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in hexc(c)]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def lab(c):
    r, g, b = [x / 255 for x in hexc(c)]
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = f(r), f(g), f(b)
    X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f2 = lambda t: t ** (1 / 3) if t > 0.008856 else (7.787 * t + 16 / 116)
    fx, fy, fz = f2(X), f2(Y), f2(Z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def deltaE(a, b):
    la, lb = lab(a), lab(b)
    return math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))


def chroma(c):
    _, a, b = lab(c)
    return math.hypot(a, b)


def darken(color, amount):
    r, g, b = hexc(color)
    k = 1 - amount
    return hx((round(r * k), round(g * k), round(b * k)))


def ensure_contrast(color, bg, need):
    c = color
    for _ in range(40):
        if contrast(c, bg) >= need:
            return c
        c = darken(c, 0.06)
    return c


def ensure_chroma(color, limit):
    c = color
    for _ in range(40):
        if chroma(c) <= limit:
            return c
        c = darken(c, 0.05)
    return c


def main():
    for pkg, draft in DRAFTS.items():
        src = MARKET / pkg
        dst = MARKET / "_review" / f"{pkg}-v5"
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        css_path = dst / "theme.css"
        css = css_path.read_text(encoding="utf-8")
        vars_now = {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[a-z0-9-]+)\s*:\s*([^;]+);", css)}
        bg = vars_now["--bg"]
        code_bg = vars_now.get("--code-bg", "#F2F2F2")
        hl_bg = vars_now.get("--warn-bg", "#F7F1D8")

        fixed = {}
        for key, value in draft.items():
            if key in CONTENT or key in SEMANTIC or key in SEMANTIC_EXTRA or key in VISIBLE:
                fixed[key] = ensure_contrast(value, bg, 4.6)
            else:
                fixed[key] = ensure_chroma(ensure_contrast(value, bg, 3.1), 29)
        fixed["code-bg"] = code_bg
        fixed["highlight-bg"] = hl_bg

        report = []
        core_min = min(deltaE(fixed[a], fixed[b]) for i, a in enumerate(CORE) for b in CORE[i + 1:])
        cont_min = min(deltaE(fixed[a], fixed[b]) for i, a in enumerate(CONTENT) for b in CONTENT[i + 1:])
        worst_contrast = min(min(contrast(fixed[k], bg) for k in CONTENT + SEMANTIC + SEMANTIC_EXTRA),
                              min(contrast(fixed[k], bg) for k in VISIBLE))
        worst_chroma = max(chroma(fixed[k]) for k in MARKERS)
        min_visible_chroma = min(chroma(fixed[k]) for k in VISIBLE)
        assert core_min >= 22 and cont_min >= 12 and worst_contrast >= 4.5 and worst_chroma <= 30 and min_visible_chroma >= 12, pkg

        block = ["", "/* ── 编辑器 Markdown 语法色（auditVersion 5 必填）──",
                 "   标记中性、内容分色：标题三级 / 粗体 / 斜体 / 代码 / 链接 / 公式 / 高亮 / 删除 / 插入 各自色相。 */",
                 ":root {"]
        for key in CONTENT + SEMANTIC + SEMANTIC_EXTRA + VISIBLE + MARKERS + BACKGROUNDS:
            block.append(f"  --md-{key}: {fixed[key]};")
        block.append("}")
        css_path.write_text(css.rstrip() + "\n" + "\n".join(block) + "\n", encoding="utf-8")

        theme = dst / "theme.json"
        entries = json.loads(theme.read_text(encoding="utf-8"))
        for e in entries:
            e["auditVersion"] = 5
            e["reviewed"] = False
            e.pop("reviewedHash", None)
        theme.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

        print(f"== _review/{pkg}-v5")
        print(f"   主色最小 ΔE {core_min:.0f}（≥22）　内容色最小 ΔE {cont_min:.0f}（≥12）　"
              f"内容最低对比 {worst_contrast:.2f}:1（≥4.5）　标记最大彩度 {worst_chroma:.0f}（≤30）　"
              f"列表/序号/任务最低彩度 {min_visible_chroma:.0f}（≥12）")
        adjusted = {k: (draft[k], fixed[k]) for k in fixed if k in draft and draft[k].lower() != fixed[k].lower()}
        for k, (old, new) in adjusted.items():
            print(f"   自动加深 --md-{k}: {old} → {new}")


if __name__ == "__main__":
    main()
