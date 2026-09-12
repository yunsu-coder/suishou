#!/usr/bin/env python3
"""亮色刷新 + 撤掉暗色版本：
    - 三套主题各自新建候选稿 plugins-market/_review/<id>-v4/
    - 只保留亮色一套（删掉 夜 / 日-夜 双生条目与暗色 CSS）
    - 纸底提亮、主色更鲜明；文字色保持门槛（正文 ≥4.5 / 次级 ≥3.5 / 主色文字 ≥4.0 /
      代码高亮 ≥3.0 / 提示色 ≥4.0），全部用真实叠底计算
    - auditVersion 升到 4；不封 reviewedHash，等你审核

用法: python3 scripts/make-light-refresh.py
"""

import json
import re
import shutil
import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MARKET = ROOT / "plugins-market"


def _load_module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

# ── 亮色刷新后的目标色板（只列会变的键）────────────────────────────────
BUBBLE = {
    "bg": "#FFFAFC", "surface": "#FFFFFF", "code-bg": "#FDF2F8",
    "text": "#2E2140", "text-secondary": "#6E5E80", "code-text": "#42285C",
    "border": "rgba(46, 33, 64, 0.12)", "border-strong": "rgba(46, 33, 64, 0.22)",
    "accent": "#FF3D9E", "accent-ink": "#B81463", "accent-soft": "rgba(255, 61, 158, 0.16)",
    "note": "#6E35FF", "note-bg": "rgba(110, 53, 255, 0.12)",
    "tip": "#0A7040", "tip-bg": "rgba(23, 160, 95, 0.14)",
    "warn": "#96660A", "warn-bg": "rgba(255, 201, 60, 0.26)",
    "danger": "#C4264C", "danger-bg": "rgba(232, 57, 95, 0.14)",
    "info": "#1A66C4", "info-bg": "rgba(30, 123, 232, 0.14)",
    "hl-kw": "#B01E96", "hl-str": "#1B7D46", "hl-num": "#6631E8",
    "hl-comment": "#7A6A88", "hl-type": "#1A66C4", "hl-func": "#96660A",
    "hl-tag": "#C4264C", "hl-attr": "#6E4200",
}

SUMI = {
    "bg": "#FCF8F0", "surface": "#FFFFFF", "code-bg": "#F5EEE0",
    "text": "#1C1A17", "text-secondary": "#6B6257",
    "border": "rgba(28, 26, 23, 0.14)", "border-strong": "rgba(28, 26, 23, 0.28)",
    "accent": "#E24A2B", "accent-ink": "#B33A20", "accent-soft": "rgba(226, 74, 43, 0.14)",
    "note": "#2F5FB0", "note-bg": "rgba(47, 95, 176, 0.12)",
    "tip": "#2F7A4F", "tip-bg": "rgba(47, 122, 79, 0.12)",
    "warn": "#8A6216", "warn-bg": "rgba(198, 146, 40, 0.18)",
    "danger": "#B33A20", "danger-bg": "rgba(179, 58, 32, 0.12)",
    "info": "#2F5FB0", "info-bg": "rgba(47, 95, 176, 0.12)",
    "hl-kw": "#B33A20", "hl-str": "#2F7A4F", "hl-num": "#2F5FB0",
    "hl-comment": "#7E7566",
}

MISTY = {
    "bg": "#FAFCF9", "sidebar": "#F1F6F2", "rail": "#EBF2EE", "status": "#E9F0EC",
    "card": "#FFFFFF", "card2": "#F3F8F4", "line": "#D6E2DA", "sel": "#D6EEE2",
    "text": "#25302B", "text-secondary": "#64736B",
    "accent": "#1FA084", "accent-ink": "#17735F", "accent2": "#C77DD6", "aux": "#E8B93C",
    "code-bg": "#F3F8F4",
    "border": "rgba(37, 48, 43, 0.14)", "border-strong": "rgba(37, 48, 43, 0.26)",
    "accent-soft": "rgba(31, 160, 132, 0.14)",
    "code-text": "#25302B", "code-border": "rgba(37, 48, 43, 0.12)",
    "note": "#2C6FB5", "note-bg": "rgba(44, 111, 181, 0.12)",
    "tip": "#0F7350", "tip-bg": "rgba(23, 142, 99, 0.13)",
    "warn": "#8F6114", "warn-bg": "rgba(232, 185, 60, 0.16)",
    "danger": "#C0434F", "danger-bg": "rgba(192, 67, 79, 0.12)",
    "info": "#2C6FB5", "info-bg": "rgba(44, 111, 181, 0.12)",
    "muted": "#8A948D",
    "hl-kw": "#177C63", "hl-str": "#8A4FB0", "hl-num": "#A8741B",
    "hl-comment": "#74837B", "hl-type": "#2C6FB5", "hl-func": "#B06A12",
    "hl-tag": "#C0434F", "hl-attr": "#6B5A2F",
    "icon.folder": "#1B7A65", "icon.doc": "#2C6FB5", "icon.other": "#8A948D",
}

# ── 多彩钩子：预览的标题 / 加粗 / 斜体各自一个色相（同饱和度、同明度带，保证和谐）──
# 追加到主题 CSS 末尾；preview.css 用 var(--h1/--h2/--h3/--strong/--em, 默认) 消费。
MULTICOLOR = {
    "theme-bubble-pop": {
        "h1": "#E0198A", "h2": "#6E35FF", "h3": "#0089A0", "strong": "#C4264C", "em": "#A86700",
        "hr": "#FFB3DC",
    },
    "theme-sumi-paper": {
        "h1": "#B33A20", "h2": "#2F5FB0", "h3": "#2F7A4F", "strong": "#8A3E7A", "em": "#8A6A1E",
        "hr": "#E0CDB4",
    },
    "theme-misty-teal": {
        "h1": "#17735F", "h2": "#2C6FB5", "h3": "#7A4FB0", "strong": "#C0434F", "em": "#178E63",
        "hr": "#CFE0D6",
    },
}

# ── 雾青：文件类型多彩重绘（其余两套的图标本来就是多色）──
MISTY_ICON_HUES = {
    "folder": "#1B7A65", "folder.open": "#2A8C74",
    "file.markdown": "#2C6FB5", "file.code": "#7A4FB0", "file.data": "#2F8F63",
    "file.image": "#2A8FA8", "file.video": "#C97A2B", "file.audio": "#B0548F",
    "file.document": "#5F6E67", "file.archive": "#8A7A2E", "file.other": "#8A948D",
    "puzzlepiece.extension": "#1B7A65", "shippingbox": "#8A7A2E", "gearshape": "#5F6E67",
    "sidebar.left": "#5F6E67", "magnifyingglass": "#5F6E67", "sparkles": "#C77DD6",
    "clock.arrow.circlepath": "#2C6FB5", "paw": "#C77DD6",
}

# 需要在 CSS 里替换 / 目标文件名
PLANS = [
    dict(pkg="theme-bubble-pop", keep="bubble-pop-light.css", drop=["bubble-pop-dark.css"],
         entry_id="bubble-pop", name="Bubble Pop", desc="像素糖果亮色主题：粉紫糖果配色、像素字体、专属像素图标与气泡彩蛋",
         colors=BUBBLE),
    dict(pkg="theme-sumi-paper", keep="sumi-day.css", drop=["sumi-night.css"],
         entry_id="sumi-paper", name="墨纸", desc="宣纸墨线、朱砂落款；亮色书写主题，自带书法字体、墨线图标与印章彩蛋",
         colors=SUMI),
    dict(pkg="theme-misty-teal", keep="theme.css", drop=[],
         entry_id="misty-teal", name="雾青", desc="纸感亮色 + 青瓷主色；植物语义图标、叶片光尘动效与开花彩蛋",
         colors=MISTY),
]


def hexc(v):
    v = v.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3,8})", v)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)), (int(h[6:8], 16) / 255 if len(h) >= 8 else 1.0)
    m = re.fullmatch(r"rgba?\(([^)]*)\)", v)
    if not m:
        raise ValueError(v)
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


def apply_colors(css, colors):
    for key, value in colors.items():
        name = key if key.startswith("--") else "--" + key
        pattern = rf"({re.escape(name)}\s*:\s*)([^;]+)(;)"
        if re.search(pattern, css):
            css = re.sub(pattern, rf"\g<1>{value}\g<3>", css, count=1)
        else:
            # 变量不存在时补在 --bg 之后
            css = re.sub(r"(--bg\s*:\s*[^;]+;)", rf"\g<1>\n  {name}: {value};", css, count=1)
    return css


def append_multicolor(css, hues):
    block = ["", "/* 多彩钩子：标题 / 加粗 / 斜体各一色相（同明度带，保持和谐） */", ":root {"]
    for key, value in hues.items():
        block.append(f"  --{key}: {value};")
    block.append("}")
    block.append("")
    return css.rstrip() + "\n" + "\n".join(block) + "\n"


REQUIRED = ["--surface", "--text-secondary", "--border", "--border-strong", "--accent-soft",
            "--code-bg", "--code-text", "--hl-kw", "--hl-str", "--hl-num", "--hl-comment",
            "--note", "--note-bg", "--tip", "--tip-bg", "--warn", "--warn-bg",
            "--danger", "--danger-bg", "--info", "--info-bg"]


def report(pkg_id, css):
    v = vars_of(css)
    bg, _ = hexc(v["--bg"])
    code_bg, _ = hexc(v["--code-bg"])
    rows = []
    for label, key, base, need in [
        ("正文", "--text", bg, 4.5), ("次级", "--text-secondary", bg, 3.5),
        ("主色文字", "--accent-ink", bg, 4.0),
    ]:
        key = key if key in v else "--accent"
        ratio = contrast(hexc(v[key])[0], base)
        rows.append((label, ratio, need, ratio >= need))
    for key in ["--hl-kw", "--hl-str", "--hl-num", "--hl-comment"]:
        ratio = contrast(hexc(v[key])[0], code_bg)
        rows.append((key.replace("--hl-", "高亮·"), ratio, 3.0, ratio >= 3.0))
    for key in ["--note", "--tip", "--warn", "--danger", "--info"]:
        fg, _ = hexc(v[key])
        t, a = hexc(v[key + "-bg"])
        ratio = contrast(fg, over(t, a, bg))
        rows.append((key.replace("--", "提示·"), ratio, 4.0, ratio >= 4.0))
    missing = [k for k in REQUIRED if k not in v]
    bad = [r for r in rows if not r[3]]
    print(f"-- {pkg_id}: " + ("全部达标" if not bad and not missing else "需修正"))
    if missing:
        print("   缺变量:", ", ".join(missing))
    for label, ratio, need, ok in rows:
        print(f"   {label:<12}{ratio:5.2f}:1  需 ≥{need}  {'OK' if ok else 'FAIL'}")
    return not bad and not missing


def main():
    ok_all = True
    for plan in PLANS:
        src = MARKET / plan["pkg"]
        dst = MARKET / "_review" / f"{plan['pkg']}-v4"
        if dst.exists():
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        for drop in plan["drop"]:
            p = dst / drop
            if p.exists():
                p.unlink()
        # CSS：换色 + 统一亮色选择器 + 改名 theme.css
        css = (dst / plan["keep"]).read_text(encoding="utf-8")
        css = apply_colors(css, plan["colors"])
        css = append_multicolor(css, MULTICOLOR[plan["pkg"]])
        if plan["keep"] != "theme.css":
            (dst / plan["keep"]).unlink()
        (dst / "theme.css").write_text(css, encoding="utf-8")
        # theme.json：单条亮色
        entries = json.loads((dst / "theme.json").read_text(encoding="utf-8"))
        keep_entry = next(e for e in entries if e.get("cssFile") == plan["keep"])
        keep_entry.update(dict(id=plan["entry_id"], name=plan["name"], desc=plan["desc"],
                               cssFile="theme.css", auditVersion=4, reviewed=False))
        keep_entry.pop("reviewedHash", None)
        keep_entry.pop("swatchHex", None)
        swatch = plan["colors"].get("accent") or plan["colors"].get("accent-ink")
        keep_entry["swatchHex"] = swatch
        (dst / "theme.json").write_text(
            json.dumps([keep_entry], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        # manifest：去掉"双生"描述
        mpath = dst / "manifest.json"
        m = json.loads(mpath.read_text(encoding="utf-8"))
        m["desc"] = plan["desc"]
        m["features"] = [f for f in m.get("features", []) if "夜" not in f and "双生" not in f]
        m["features"].insert(0, "亮色单主题：不做暗色半成品，之后另行补充")
        mpath.write_text(json.dumps(m, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        # 雾青：文件类型多彩重绘（其余两套本来就有）
        if plan["pkg"] == "theme-misty-teal":
            mt = _load_module("make-misty-teal")
            for key, fname, fn, _tier in mt.ICON_MAP:
                color = MISTY_ICON_HUES[key]
                mt.render_icon(fn, color, 256).save(dst / f"icons/{fname}-256.png")
                mt.render_icon(fn, color, 64).save(dst / f"icons/{fname}-64.png")
            print("   图标已按文件类型多彩重绘（19 个槽位）")
        print(f"\n== 候选稿 plugins-market/_review/{plan['pkg']}-v4（亮色单主题）")
        ok_all &= report(plan["pkg"], css)
    print("\n" + ("全部候选达标，等人工审核。" if ok_all else "有未达标项，需要继续调色。"))


if __name__ == "__main__":
    main()
