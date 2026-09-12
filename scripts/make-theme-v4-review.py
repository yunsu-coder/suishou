#!/usr/bin/env python3
"""老主题 v4 升级评审图：改前 / 改后对比（提示色 + 代码高亮 + 对比度数据）。

用法: python3 scripts/make-theme-v4-review.py [输出.png]
"""

import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import importlib.util


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


gt = _load("make-game-themes")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO

CALLOUTS = [("--note", "note", "提示"), ("--tip", "tip", "成功"), ("--warn", "warn", "警告"),
            ("--danger", "danger", "危险"), ("--info", "info", "信息")]


def hexc(v):
    v = v.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3,8})", v)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)), (int(h[6:8], 16) / 255 if len(h) >= 8 else 1.0)
    m = re.fullmatch(r"rgba?\(([^)]*)\)", v)
    p = [x.strip() for x in m.group(1).split(",")]
    return tuple(int(float(x)) for x in p[:3]), (float(p[3]) if len(p) > 3 else 1.0)


def over(f, a, b):
    return tuple(round(f[i] * a + b[i] * (1 - a)) for i in range(3))


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in c]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def vars_of(css):
    return {m.group(1): m.group(2).strip() for m in re.finditer(r"(--[a-z-]+)\s*:\s*([^;]+);", css)}


def callout_card(d, x, y, w, v, label, ratio, ok):
    bg, _ = hexc(v["--bg"])
    text, _ = hexc(v["--text"])
    tint, alpha = hexc(v["--" + label + "-bg"])
    accent, _ = hexc(v["--" + label])
    base = over(tint, alpha, bg)
    d.rounded_rectangle([x, y, x + w, y + 86], radius=10, fill=base, outline=over(text, 0.18, base))
    d.rounded_rectangle([x, y, x + 4, y + 86], radius=2, fill=accent)
    T(d, x + 16, y + 12, label, F(HIRA, 12, 2), accent)
    T(d, x + 16, y + 34, "这是一段提示块内容，用来检查文字是否清楚。", F(HIRA, 12), text)
    T(d, x + 16, y + 58, f"对比 {ratio:.2f}:1" + ("　达标" if ok else "　未达标"), F(HIRA, 11),
      text if ok else accent)


def code_card(d, x, y, w, v, tag):
    bg, _ = hexc(v["--bg"])
    code_bg, _ = hexc(v["--code-bg"])
    text, _ = hexc(v["--text"])
    comment, _ = hexc(v["--hl-comment"])
    kw, _ = hexc(v["--hl-kw"])
    string, _ = hexc(v["--hl-str"])
    num, _ = hexc(v["--hl-num"])
    d.rounded_rectangle([x, y, x + w, y + 96], radius=10, fill=code_bg, outline=over(text, 0.2, bg))
    T(d, x + 14, y + 10, tag, F(HIRA, 11, 2), text)
    T_mix(d, x + 14, y + 30, "// 注释：写完记得保存", F(MENLO, 12), F(HIRA, 12), comment)
    T(d, x + 14, y + 54, "let x =", F(MENLO, 12), text)
    T(d, x + 86, y + 54, "42", F(MENLO, 12), num)
    T(d, x + 112, y + 54, "return", F(MENLO, 12), kw)
    T_mix(d, x + 160, y + 50, '"雾青"', F(MENLO, 12), F(HIRA, 12), string)
    cb, _ = hexc(v["--code-bg"])
    r = contrast(comment, cb)
    T(d, x + 14, y + 74, f"注释对比 {r:.2f}:1" + ("　达标" if r >= 3.0 else "　未达标"), F(HIRA, 11),
      text if r >= 3.0 else comment)


def theme_block(img, d, y, name, old_v, new_v, changes, sub):
    d.rounded_rectangle([40, y, 1800, y + 440], radius=16, fill="#111722", outline="#1F2937")
    T(d, 70, y + 18, name, F(HIRA, 19, 2), "#EFF4FF")
    T(d, 170, y + 46, sub, F(HIRA, 12), "#8FA0BB")
    d.rounded_rectangle([70, y + 44, 150, y + 66], radius=6, fill=new_v["--bg"], outline="#2A3648")

    for i, (key, label, title) in enumerate(CALLOUTS):
        fg_old, _ = hexc(old_v[key])
        t_old, a_old = hexc(old_v[key + "-bg"])
        b_old, _ = hexc(old_v["--bg"])
        r_old = contrast(fg_old, over(t_old, a_old, b_old))
        fg_new, _ = hexc(new_v[key])
        t_new, a_new = hexc(new_v[key + "-bg"])
        b_new, _ = hexc(new_v["--bg"])
        r_new = contrast(fg_new, over(t_new, a_new, b_new))
        callout_card(d, 70 + i * 350, y + 96, 320, old_v, label, r_old, r_old >= 4.0)
        callout_card(d, 70 + i * 350, y + 224, 320, new_v, label, r_new, r_new >= 4.0)

    code_card(d, 70, y + 330, 900, old_v, "改前 · 代码高亮")
    code_card(d, 1000, y + 330, 900, new_v, "改后 · 代码高亮")

    T(d, 70, y + 74, "改前", F(HIRA, 12, 2), "#8FA0BB")
    T(d, 70, y + 202, "改后（v4）", F(HIRA, 12, 2), "#7FD1A8")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/game/theme-v4-upgrade.png"
    pairs = [
        ("Bubble Pop · 亮色（像素糖果）", "theme-bubble-pop", "bubble-pop-light.css"),
        ("墨纸 · 日（宣纸墨线）", "theme-sumi-paper", "sumi-day.css"),
    ]
    W, H = 1840, 1230
    img, d = gt.page(W, H)
    T(d, 48, 34, "老主题升级 · auditVersion 4", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "按新规则补齐：提示块与代码高亮的真实可读性。只改这几个色值，其他一律不动。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline="#7FD1A8")
    T(d, W - 189, 68, "候选稿 · 等你审核封版", F(HIRA, 13), "#7FD1A8", anchor="mm")

    for i, (name, pkg, css_name) in enumerate(pairs):
        old_css = (ROOT / "plugins-market" / pkg / css_name).read_text(encoding="utf-8")
        new_css = (ROOT / "plugins-market/_review" / f"{pkg}-v4" / css_name).read_text(encoding="utf-8")
        changes = json.loads((ROOT / "plugins-market/_review" / f"{pkg}-v4" / "theme.json").read_text(encoding="utf-8"))
        theme_block(img, d, 130 + i * 470, name, vars_of(old_css), vars_of(new_css), changes,
                    f"plugins-market/_review/{pkg}-v4　·　只改了提示色与代码注释色的明度")

    d.rounded_rectangle([48, H - 160, 1792, H - 40], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 144, "四个可量化门槛（v4 起对全部主题生效）", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, H - 116, "① 提示块文字 / 自身提示底 ≥4.0:1　② 代码高亮 / 代码底 ≥3.0:1　③ 禁止渐变　④ 标题必须有自己的字体 + 动效 ≥2 项",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 88, "其他规则：预览变量必须齐备（21 个）、图标统一 ≥64×64 正方形、字体/图标/彩蛋/体积门槛不变。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 60, "这两套候选已通过自动审计（只差人工审核）；通过后我会封 reviewedHash、安装并重启应用。",
      F(HIRA, 13), "#B9C6DC")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
