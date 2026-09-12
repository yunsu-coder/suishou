#!/usr/bin/env python3
"""编辑器 Markdown 语法配色评审稿：线上（系统色）vs 提议（跟主题同源的多色谱）。

用法: python3 scripts/make-editor-syntax-review.py [输出.png]
"""

import importlib.util
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
    base = hexc("#FFFFFF")
    a = float(p[3]) if len(p) > 3 else 1.0
    return tuple(round(int(p[i]) * a + base[i] * (1 - a)) for i in range(3))


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in c]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast_hex(a, b):
    la, lb = lum(hexc(a)), lum(hexc(b))
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def vars_of(css):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[a-z-]+)\s*:\s*([^;]+);", css)}


def over(fg, alpha, bg):
    c = hexc(fg)
    b = hexc(bg)
    return "#%02X%02X%02X" % tuple(round(c[i] * alpha + b[i] * (1 - alpha)) for i in range(3))


def solid(color, bg):
    """rgba(...) → 叠在 bg 上的实色；hex 原样返回。"""
    m = re.fullmatch(r"rgba?\(([^)]*)\)", color.strip())
    if not m:
        return color
    p = [x.strip() for x in m.group(1).split(",")]
    a = float(p[3]) if len(p) > 3 else 1.0
    return over("#%02X%02X%02X" % tuple(int(float(p[i])) for i in range(3)), a, bg)


# 线上（当前实现）写死的系统色 —— 与主题无关
BEFORE = dict(
    heading="#6B4FD9", marker="#9A9A9A", bold="#FF9500", italic="#00A0A0", code="#FF9500",
    code_text="#8A8A8A", linkLabel="#007AFF", linkURL="#AF52DE", quote="#9A9A9A",
    bullet="#6E6E6E", math="#FF2D55", highlight="#FF3B30", strike="#9A9A9A",
    insert="#34C759", hr="#9A9A9A", table="#9A9A9A", fence="#FF9500",
)


def proposal(v):
    """提议配色：全部取自主题自身变量（跟预览同一套色相）。"""
    p = dict(
        heading=v.get("--h1", v["--text"]),
        heading2=v.get("--h2", v["--text"]),
        marker=v.get("--text-secondary", v["--text"]),
        bold=v.get("--strong", v["--text"]),
        bold_mark=over(v.get("--strong", v["--text"]), 0.55, v["--bg"]),
        italic=v.get("--em", v["--text"]),
        code=v.get("--accent", v["--text"]),
        code_text=v.get("--code-text", v["--text"]),
        code_bg=solid(v.get("--code-bg", "#F0F0F0"), v["--bg"]),
        linkLabel=v.get("--h2", v["--text"]),
        linkURL=v.get("--hl-func", v["--accent"]),
        quote=v.get("--text-secondary", v["--text"]),
        quote_mark=v.get("--accent", v["--text"]),
        bullet=v.get("--accent", v["--text"]),
        number=v.get("--hl-num", v["--text"]),
        task_done=v.get("--tip", v["--text"]),
        task_open=v.get("--text-secondary", v["--text"]),
        math=v.get("--hl-str", v["--text"]),
        highlight=v.get("--hl-num", v["--text"]),
        highlight_bg=solid(v.get("--warn-bg", "#F7F1D8"), v["--bg"]),
        strike=v.get("--danger", v["--text"]),
        insert=v.get("--tip", v["--text"]),
        hr=v.get("--hr", v.get("--border-strong", "#DDD")),
        table=v.get("--h3", v["--text"]),
        fence=v.get("--hl-type", v["--text"]),
        callout=v.get("--warn", v["--text"]),
    )
    return p


def span(text, color, weight=0, bg=None, strike=False):
    return dict(text=text, color=color, weight=weight, bg=bg, strike=strike)


LINES = [
    ("h1", [("!", 0)]),
]


def draw_run(d, x, y, runs, size=13):
    """按段绘制一行（CJK 回落中文字体，背景块先铺底）。"""
    for r in runs:
        text = r["text"]
        if r.get("bg"):
            w = T_mix(d, x, y, text, F(MONO, size), F(HIRA, size), r["color"])
            d.rounded_rectangle([x - 3, y - 1, w + 3, y + size + 6], radius=4, fill=r["bg"])
        if r.get("strike"):
            w = T_mix(d, x, y, text, F(MONO, size), F(HIRA, size), r["color"])
            d.line([(x, y + size * 0.62), (w, y + size * 0.62)], fill=r["color"], width=2)
        f_lat = F(MONO, size)
        f_cjk = F(HIRA, size)
        if r["weight"] == 2:
            f_cjk = F(HIRA, size, 2)
        x = T_mix(d, x, y, text, f_lat, f_cjk, r["color"])
    return x


def sample_lines(kind):
    """返回每一行的 (runs 工厂)；kind = 'before' | 'after'"""
    if kind == "before":
        def mk(c, extra=None):
            base = dict(BEFORE)
            base.update(extra or {})
            return base
    return None


def build(colors, mode):
    """mode: 'before' 用固定系统色，'after' 用主题色"""
    c = colors
    out = []
    out.append([span("#", c["marker"] if mode == "after" else c["heading"], 2),
                span(" 一级标题", c["heading"], 2)])
    out.append([span("##", c["heading2"] if mode == "after" else c["heading"], 2),
                span(" 二级标题", c["heading2"] if mode == "after" else c["heading"], 2)])
    out.append([span("**", c["bold_mark"] if mode == "after" else c["marker"], 2),
                span("粗体", c["bold"], 2),
                span("**", c["bold_mark"] if mode == "after" else c["marker"], 2),
                span(" 与 ", c.get("text", c["heading"])),
                span("*", c["marker"]), span("斜体", c["italic"]), span("*", c["marker"])])
    out.append([span("行内 ", "#" + "25302B" if mode == "before" else c.get("text", c["heading"])),
                span("`let x = 1`", c["code"], bg=c["code_bg"] if mode == "after" else None),
                span(" 与 ", c.get("text", c["heading"])),
                span("[", c["marker"]), span("链接", c["linkLabel"]), span("](", c["marker"]),
                span("https://a.b", c["linkURL"]), span(")", c["marker"])])
    out.append([span("![", c["marker"]), span("图片", c["linkLabel"]), span("](", c["marker"]),
                span("source/img/a.png", c["linkURL"]), span(")", c["marker"])])
    out.append([span("> ", c["quote_mark"] if mode == "after" else c["quote"]),
                span("引用：第七朵花开了", c["quote"])])
    out.append([span("- ", c["bullet"]), span("列表项　", c.get("text", c["heading"])),
                span("- [x] ", c["task_done"] if mode == "after" else c["bullet"]),
                span("已完成　", c["task_done"] if mode == "after" else c.get("text", c["heading"])),
                span("- [ ] ", c["task_open"] if mode == "after" else c["bullet"]),
                span("待办", c["task_open"] if mode == "after" else c.get("text", c["heading"]))])
    out.append([span("1. ", c["number"] if mode == "after" else c["bullet"]),
                span("有序列表", c.get("text", c["heading"]))])
    out.append([span("==", c["highlight"]), span("高亮", c["highlight"], bg=c["highlight_bg"] if mode == "after" else None),
                span("==", c["highlight"]), span(" ", c.get("text", c["heading"])),
                span("~~", c["strike"] if mode == "after" else c["marker"]),
                span("删除", c["strike"] if mode == "after" else c["quote"], strike=True),
                span("~~", c["strike"] if mode == "after" else c["marker"]), span(" ", c.get("text", c["heading"])),
                span("++", c["insert"]), span("插入", c["insert"]), span("++", c["insert"])])
    out.append([span("公式 ", c.get("text", c["heading"])), span("$E=mc^2$", c["math"]),
                span("　脚注 ", c.get("text", c["heading"])), span("[^1]", c["table"] if mode == "after" else c["quote"])])
    out.append([span("---", c["hr"]), span("  分隔线", c["quote"])])
    out.append([span("| ", c["table"] if mode == "after" else c["quote"]),
                span("列 A", c.get("text", c["heading"])),
                span(" | ", c["table"] if mode == "after" else c["quote"]),
                span("列 B", c.get("text", c["heading"])),
                span(" |", c["table"] if mode == "after" else c["quote"])])
    out.append([span("```", c["fence"] if mode == "after" else c["marker"]),
                span("swift", c["fence"] if mode == "after" else c["code"])])
    out.append([span("::: ", c["callout"]), span("tip", c["callout"], 2),
                span(" 提示块", c.get("text", c["heading"]))])
    return out


def panel(img, d, x, y, w, h, title, subtitle, runs_list, v, tone):
    d.rounded_rectangle([x, y, x + w, y + h], radius=12, fill=v["--bg"], outline="#2A3648")
    T(d, x + 16, y + 12, title, F(HIRA, 14, 2), tone)
    T(d, x + 16, y + 34, subtitle, F(HIRA, 11), v.get("--text-secondary", "#777"))
    yy = y + 60
    for runs in runs_list:
        draw_run(d, x + 16, yy, runs)
        yy += 30


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/game/editor-syntax.png"
    themes = [
        ("theme-bubble-pop", "Bubble Pop（像素糖果）"),
        ("theme-sumi-paper", "墨纸（宣纸墨线）"),
        ("theme-misty-teal", "雾青（青瓷纸感）"),
    ]
    W, H = 1840, 2140
    img, d = gt.page(W, H)
    T(d, 48, 34, "编辑器 Markdown 语法配色 · 评审稿", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "左＝线上现状（写死的系统色，与主题无关、且多处共用同色）；右＝提议（跟主题同源的多色谱 + 标记/内容分级）。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 350, 46, W - 48, 90], radius=20, fill="#161C26", outline="#E0A0A0")
    T(d, W - 199, 68, "未动手 · 等你审核", F(HIRA, 13), "#E0A0A0", anchor="mm")

    for i, (pkg, name) in enumerate(themes):
        y = 130 + i * 660
        d.rounded_rectangle([40, y, 1800, y + 636], radius=16, fill="#111722", outline="#1F2937")
        T(d, 70, y + 18, name, F(HIRA, 19, 2), "#EFF4FF")
        v = vars_of((ROOT / "plugins-market" / pkg / "theme.css").read_text(encoding="utf-8"))
        after = proposal(v)
        before = dict(after)
        before.update({"text": "#25302B" if pkg != "theme-misty-teal" else "#25302B"})
        # 线上固定色覆盖
        for k, val in BEFORE.items():
            if k in before:
                before[k] = val
        before["code_bg"] = None
        before["highlight_bg"] = None
        before.setdefault("text", "#333333")

        panel(img, d, 70, y + 56, 800, 500, "线上现状", "系统色，跟主题不搭；多种语法同色",
              build(before, "before"), v, "#E0A0A0")
        panel(img, d, 900, y + 56, 800, 500, "提议：主题同源多色谱", "标记弱化、内容着色，标记与内容分工",
              build(after, "after"), v, "#7FD1A8")

        # 现状实测问题（用当前写死的系统色算对比度）
        bg = v["--bg"]
        problems = []
        for label, color in [("粗体/行内代码 #FF9500", "#FF9500"), ("引用/分隔线/删除线 #9A9A9A", "#9A9A9A"),
                             ("高亮 #FF3B30", "#FF3B30"), ("链接 #007AFF", "#007AFF")]:
            r = contrast_hex(color, bg)
            if r < 4.5:
                problems.append(f"{label} → {r:.2f}:1 ✗")
        T(d, 70, y + 562, "现状实测：" + "　".join(problems) + "　｜　粗体与行内代码同色、引用/分隔线/表格/删除线同色",
          F(HIRA, 11), "#E0A0A0")

        # 数据：每个色相的对比度
        rows = [("标题", after["heading"]), ("标题2", after["heading2"]), ("粗体", after["bold"]),
                ("斜体", after["italic"]), ("行内代码", after["code"]), ("链接", after["linkLabel"]),
                ("URL", after["linkURL"]), ("列表", after["bullet"]), ("公式", after["math"]),
                ("高亮", after["highlight"]), ("删除", after["strike"]), ("插入", after["insert"]),
                ("标题3/表格", after["table"])]
        T(d, 70, y + 578, "提议配色在各主题纸底上的对比度（正文级 ≥4.5:1，标记级 ≥3.0:1）", F(HIRA, 12, 2), "#EFF4FF")
        for k, (label, color) in enumerate(rows):
            cx = 70 + (k % 7) * 118
            yy = y + 600 + (k // 7) * 0
            ratio = contrast_hex(color, v["--bg"])
            d.rounded_rectangle([cx, y + 596, cx + 22, y + 618], radius=5, fill=color, outline="#2A3648")
            T(d, cx + 28, y + 598, f"{label} {ratio:.1f}", F(HIRA, 10), "#B9C6DC" if ratio >= 4.5 else "#E0C080")

    d.rounded_rectangle([48, H - 210, 1792, H - 40], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 194, "我想干什么（等你批准再动手）", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, H - 166, "① 编辑器不再用系统色：标题 / 粗体 / 斜体 / 代码 / 链接 / 列表 / 公式 / 高亮 / 删除 / 插入 全部改为读当前主题的色相（与预览同一套）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 140, "② 标记与内容分级：**  #  >  -  ``` 这些标记用弱化色（62% 叠底），内容用饱和色 —— 结构一眼可见但不吵。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 114, "③ 拆掉共用色：行内代码不再跟粗体同色；引用 / 分隔线 / 表格 / 删除线 / 列表各自有独立色相。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 88, "④ 新增 3 个 token：Callout `::: tip`、脚注 [^1]、HTML 标签 —— 都有各自颜色（现在没有）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 62, "⑤ 加硬门槛：语法色在纸底上 ≥4.5:1（标记 ≥3.0:1）写进主题 v4 审计；tokenizer 与后台解析逻辑不动，打字性能不变。",
      F(HIRA, 13), "#B9C6DC")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
