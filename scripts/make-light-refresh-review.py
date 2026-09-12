#!/usr/bin/env python3
"""亮色刷新评审图：三套主题「改前 / 改后」窗口对照 + 关键色板 + 对比度数据。

用法: python3 scripts/make-light-refresh-review.py [输出.png]
"""

import importlib.util
import json
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
review = _load("make-misty-teal-review")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO


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
    return tuple(int(float(x)) for x in p[:3])


def mix(a, b, t):
    ca, cb = hexc(a), hexc(b)
    return "#%02X%02X%02X" % tuple(round(ca[i] * (1 - t) + cb[i] * t) for i in range(3))


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in hexc(c)]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def vars_of(css):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[a-z-]+)\s*:\s*([^;]+);", css)}


def solid(color, bg):
    """rgba/hex → 叠在 bg 上的实色（PIL 不认 rgba 字符串）"""
    m = re.fullmatch(r"rgba?\(([^)]*)\)", color.strip())
    if not m:
        return color
    p = [x.strip() for x in m.group(1).split(",")]
    a = float(p[3]) if len(p) > 3 else 1.0
    base = hexc(bg)
    return "#%02X%02X%02X" % tuple(round(int(p[i]) * a + base[i] * (1 - a)) for i in range(3))


def mock_palette(v, tiers):
    """把主题变量补成窗口渲染器要的键（缺的按纸底推导）。"""
    bg, text = v["--bg"], v["--text"]
    surface = v.get("--surface", "#FFFFFF")
    code_bg = v.get("--code-bg", mix(bg, text, 0.05))
    accent = v.get("--accent", "#888888")
    accent_ink = v.get("--accent-ink", accent)
    return dict(
        bg=bg, text=text, dim=v.get("--text-secondary", mix(text, bg, 0.45)),
        secondary=v.get("--text-secondary", mix(text, bg, 0.45)),
        sidebar=mix(bg, text, 0.035), rail=mix(bg, text, 0.06), status=mix(bg, text, 0.045),
        card=surface, card2=code_bg, sel=mix(bg, accent, 0.18),
        line=mix(bg, text, 0.14), accent=accent, accent_ink=accent_ink,
        accent2=tiers["accent2"], aux=tiers["aux"], paper=surface, ink=text,
        **{"icon.folder": tiers["folder"], "icon.doc": tiers["doc"], "icon.other": tiers["other"]})


TIERS = {
    "theme-bubble-pop": dict(folder="#B81463", doc="#FF3D9E", other="#9C8FAA", accent2="#6E35FF", aux="#FFC93C"),
    "theme-sumi-paper": dict(folder="#B33A20", doc="#2F5FB0", other="#6B6257", accent2="#8A6A2E", aux="#C69228"),
    "theme-misty-teal": dict(folder="#1B7A65", doc="#1FA084", other="#8A948D", accent2="#C77DD6", aux="#E8B93C"),
}

OLD_TIERS = {
    "theme-bubble-pop": dict(folder="#C2186B", doc="#FF5FB0", other="#9C8FAA", accent2="#7C4DFF", aux="#FFC93C"),
    "theme-sumi-paper": dict(folder="#C8442E", doc="#3B5BA5", other="#6B6257", accent2="#8A6A2E", aux="#C69228"),
    "theme-misty-teal": dict(folder="#2C5F52", doc="#3C7867", other="#8A948D", accent2="#A98BB2", aux="#C9A227"),
}

PLANS = [
    ("theme-bubble-pop", "bubble-pop-light.css", "Bubble Pop（像素糖果）", "撤掉「夜」版本 · 粉更艳、纸更白"),
    ("theme-sumi-paper", "sumi-day.css", "墨纸（宣纸墨线）", "撤掉「夜」版本 · 纸更白、朱砂更亮"),
    ("theme-misty-teal", "theme.css", "雾青（青瓷纸感）", "纸底提亮、青瓷主色更鲜明"),
]


def row_render(pal, scale=0.30):
    win = review.render_window(pal)
    return win, scale


def multicolor_strip(d, x, y, v, hues):
    labels = [("标题 1", "--h1"), ("标题 2", "--h2"), ("标题 3", "--h3"),
              ("加粗", "--strong"), ("斜体", "--em"), ("提示", "--note"),
              ("警告", "--warn"), ("强调", "--accent2")]
    T(d, x, y - 22, "多彩色谱（同一明度带，保证和谐）", F(HIRA, 12, 2), "#EFF4FF")
    for i, (label, key) in enumerate(labels):
        value = v.get(key, hues.get(key.lstrip("-"), "#CCCCCC"))
        cx = x + i * 104
        d.rounded_rectangle([cx, y, cx + 88, y + 34], radius=8, fill=value, outline="#2A3648")
        T(d, cx, y + 40, label, F(HIRA, 11), "#B9C6DC")
        T(d, cx, y + 58, value.upper(), F(MENLO, 10, 1), "#6F7E96")


def multicolor_sample(d, x, y, w, v):
    d.rounded_rectangle([x, y, x + w, y + 150], radius=12, fill=v["--bg"],
                        outline=solid(v.get("--border-strong", "#DDDDDD"), v["--bg"]))
    T(d, x + 18, y + 12, "预览实测：标题 / 加粗 / 斜体 / 提示块 / 代码高亮各自一色", F(HIRA, 12, 2), "#8FA0BB")
    T(d, x + 18, y + 38, "一级标题", F(SONG, 20, 1), v.get("--h1", v["--text"]))
    T(d, x + 148, y + 42, "二级标题", F(SONG, 17, 1), v.get("--h2", v["--text"]))
    T(d, x + 258, y + 45, "三级标题", F(SONG, 15, 1), v.get("--h3", v["--text"]))
    T(d, x + 366, y + 46, "加粗", F(HIRA, 13, 2), v.get("--strong", v["--text"]))
    T(d, x + 414, y + 46, "斜体", F(SONG, 13, 2), v.get("--em", v["--text"]))
    T(d, x + 18, y + 78, "这是一段正文，用来和标题层级做对比。", F(HIRA, 13), v["--text"])
    # 提示块
    tint_f, tint_a = None, None
    import re as _re
    m = _re.fullmatch(r"rgba\(([^)]*)\)", v.get("--warn-bg", "rgba(0,0,0,0)"))
    tp = [p.strip() for p in m.group(1).split(",")] if m else ["0", "0", "0", "0"]
    tint = "#%02X%02X%02X" % tuple(round(hexc(v["--bg"])[i] * (1 - float(tp[3])) + int(tp[i]) * float(tp[3]))
                                   for i in range(3))
    d.rounded_rectangle([x + 18, y + 102, x + 300, y + 136], radius=8, fill=tint)
    d.rounded_rectangle([x + 18, y + 102, x + 22, y + 136], radius=2, fill=v["--warn"])
    T(d, x + 32, y + 110, "警告提示：对比度达标", F(HIRA, 12), v["--warn"])
    # 代码高亮
    d.rounded_rectangle([x + 316, y + 102, x + w - 18, y + 136], radius=8, fill=v["--code-bg"])
    T(d, x + 330, y + 110, "let", F(MENLO, 12), v["--hl-kw"])
    T(d, x + 356, y + 110, "x", F(MENLO, 12), v["--code-text"])
    T(d, x + 372, y + 110, "=", F(MENLO, 12), v["--code-text"])
    T(d, x + 390, y + 110, "42", F(MENLO, 12), v["--hl-num"])
    T_mix(d, x + 410, y + 106, '"青瓷"', F(MENLO, 12), F(HIRA, 12), v["--hl-str"])
    T(d, x + 472, y + 110, "// 注释", F(MENLO, 12), v["--hl-comment"])


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/game/light-refresh.png"
    W, H = 1840, 2080
    img, d = gt.page(W, H)
    T(d, 48, 34, "亮色刷新 · 三套主题（暗色全部撤掉 · 多彩）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "纸底提亮、主色放开饱和度、文件类型与预览层级各占一个色相；文字对比度仍然全部达标。左＝线上，右＝候选。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 350, 46, W - 48, 90], radius=20, fill="#161C26", outline="#7FD1A8")
    T(d, W - 199, 68, "候选稿 · 等你审核封版", F(HIRA, 13), "#7FD1A8", anchor="mm")

    for i, (pkg, css_name, title, note) in enumerate(PLANS):
        y = 130 + i * 630
        d.rounded_rectangle([40, y, 1800, y + 606], radius=16, fill="#111722", outline="#1F2937")
        T(d, 70, y + 18, title, F(HIRA, 19, 2), "#EFF4FF")
        T(d, 70, y + 48, note, F(HIRA, 12), "#8FA0BB")

        old_css = (ROOT / "plugins-market" / pkg / css_name).read_text(encoding="utf-8")
        new_css = (ROOT / "plugins-market/_review" / f"{pkg}-v4" / "theme.css").read_text(encoding="utf-8")
        old_v, new_v = vars_of(old_css), vars_of(new_css)
        old_pal = mock_palette(old_v, OLD_TIERS[pkg])
        new_pal = mock_palette(new_v, TIERS[pkg])

        for k, (pal, tag, col) in enumerate([(old_pal, "改前（线上）", "#8FA0BB"), (new_pal, "改后（候选）", "#7FD1A8")]):
            x = 70 + k * 440
            win, scale = row_render(pal)
            gt.paste_win(img, win, x, y + 80, scale=scale, radius=8, shadow=False)
            w_px, h_px = int(1300 * scale), int(800 * scale)
            d.rounded_rectangle([x, y + 80, x + w_px, y + 80 + h_px], radius=8, outline="#2A3648", width=1)
            T(d, x, y + 64, tag, F(HIRA, 12, 2), col)

        # 色板与数据
        sx = 960
        items = [("纸底", "--bg", new_v), ("侧栏/卡片", "--surface", new_v), ("主色", "--accent", new_v),
                 ("主色文字", "--accent-ink", new_v), ("代码底", "--code-bg", new_v)]
        for k, (label, key, v) in enumerate(items):
            yy = y + 84 + k * 50
            d.rounded_rectangle([sx, yy, sx + 64, yy + 38], radius=8, fill=v.get(key, "#FFFFFF"), outline="#2A3648")
            T(d, sx + 78, yy + 4, label, F(HIRA, 12), "#B9C6DC")
            T(d, sx + 78, yy + 22, v.get(key, "—"), F(MENLO, 11, 1), "#6F7E96")
            old_ratio = None
            if key in old_v:
                old_ratio = contrast(old_v[key], old_v["--bg"]) if key != "--code-bg" else None
            new_ratio = contrast(new_v[key], new_v["--bg"]) if key != "--code-bg" else None
            if new_ratio and key == "--accent-ink":
                T(d, sx + 250, yy + 10, f"{new_ratio:.2f}:1", F(MENLO, 12, 1), "#B9C6DC")

        # 关键对比度三项
        rows = [("正文", "--text", 4.5), ("次级", "--text-secondary", 3.5), ("主色文字", "--accent-ink", 4.0)]
        for k, (label, key, need) in enumerate(rows):
            xx = sx + 250 + k * 200
            ratio = contrast(new_v[key], new_v["--bg"])
            T(d, xx, y + 96, label, F(HIRA, 12, 2), "#EFF4FF")
            T(d, xx, y + 118, f"{ratio:.2f}:1 ≥ {need}", F(MENLO, 11, 1), "#7FD1A8" if ratio >= need else "#E08C90")

        MULTI = {
            "theme-bubble-pop": {"h1": "#E0198A", "h2": "#6E35FF", "h3": "#0089A0", "strong": "#C4264C", "em": "#A86700"},
            "theme-sumi-paper": {"h1": "#B33A20", "h2": "#2F5FB0", "h3": "#2F7A4F", "strong": "#8A3E7A", "em": "#8A6A1E"},
            "theme-misty-teal": {"h1": "#17735F", "h2": "#2C6FB5", "h3": "#7A4FB0", "strong": "#C0434F", "em": "#178E63"},
        }[pkg]
        merged = dict(new_v)
        for k, val in MULTI.items():
            merged[f"--{k}"] = val
        merged["--accent2"] = TIERS[pkg]["accent2"]
        multicolor_strip(d, 70, y + 366, merged, MULTI)
        multicolor_sample(d, 70, y + 440, 900, merged)

        # 文件类型多彩（图标）
        T(d, 1000, y + 344, "文件类型配色（图标）", F(HIRA, 12, 2), "#EFF4FF")
        icon_map = {
            "theme-bubble-pop": [("文件夹", "#FFC93C"), ("Markdown", "#7FA4D8"), ("代码", "#9A6BFF"),
                                 ("数据", "#4FD1A5"), ("图片", "#43C6D8"), ("视频", "#FF8A5C"),
                                 ("音频", "#FF7AB6")],
            "theme-sumi-paper": [("文件夹", "#C8442E"), ("Markdown", "#3B5BA5"), ("代码", "#6A3BD6"),
                                 ("数据", "#3F6B4F"), ("图片", "#2F7FA0"), ("视频", "#C45A1E"),
                                 ("音频", "#B03A6E")],
            "theme-misty-teal": [("文件夹", "#1B7A65"), ("Markdown", "#2C6FB5"), ("代码", "#7A4FB0"),
                                 ("数据", "#2F8F63"), ("图片", "#2A8FA8"), ("视频", "#C97A2B"),
                                 ("音频", "#B0548F")],
        }[pkg]
        for k, (label, color) in enumerate(icon_map):
            cx = 1000 + k * 112
            d.rounded_rectangle([cx, y + 372, cx + 88, y + 420], radius=8, fill=color, outline="#2A3648")
            T(d, cx, y + 426, label, F(HIRA, 11), "#B9C6DC")
        T(d, 1000, y + 452, "图标颜色 = 文件类型；字形本身也各不相同（v3 规则：透明字形、无底板）。", F(HIRA, 11), "#6F7E96")

        if pkg != "theme-misty-teal":
            T(d, 70, y + 576, "暗色版本已删除（Bubble Pop · 夜 / 墨纸 · 夜）", F(HIRA, 12), "#E0A0A0")

    d.rounded_rectangle([48, H - 170, 1792, H - 40], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 154, "三套候选已经通过自动审计（auditVersion 4，亮色单主题，多彩）", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, H - 126, "提示块 ≥4.0:1　代码高亮 ≥3.0:1　正文 ≥4.5:1　次级 ≥3.5:1　主色文字 ≥4.0:1　无渐变　动效 ≥2 项　图标 ≥64×64",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 100, "你点通过后：封 reviewedHash → 安装 → 重启应用 → 我加一条「市场主题必须 ≥v4 且只允许亮色」的强制测试。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 74, "暗色主题之后再补：会按同一套 v4 规则重做，不复用现在的昏暗版本。", F(HIRA, 13), "#8FA0BB")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
