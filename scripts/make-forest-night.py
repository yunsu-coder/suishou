#!/usr/bin/env python3
"""生成「深林夜」暗色主题包（评审稿）：色板取自 make-dark-proposals 的 forest-night，保证与提案一致。

用法: python3 scripts/make-forest-night.py [输出目录]
默认输出: plugins-market/_review/theme-forest-night-v1
"""

import importlib.util
import json
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / "scripts" / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


dark = _load("make-dark-proposals")
b3 = _load("make-garden-b3")

SEED = next(t for t in dark.THEMES if t["id"] == "forest-night")
P = dark.build_palette(SEED)
METRICS = dark.metrics(P)

# 图标：每个语义槽位一个色相（暗底上提亮，保持同一明度带）
ICON_HUES = {
    "folder": "#3FD1A5", "folder.open": "#5FDDB8",
    "file.markdown": "#86B4FF", "file.code": "#B49BFF", "file.data": "#76D98F",
    "file.image": "#5FD3E0", "file.video": "#E8955A", "file.audio": "#FF9ED8",
    "file.document": "#A8B8AC", "file.archive": "#D8C071", "file.other": "#8FA79A",
    "puzzlepiece.extension": "#3FD1A5", "shippingbox": "#D8C071", "gearshape": "#A8B8AC",
    "sidebar.left": "#A8B8AC", "magnifyingglass": "#A8B8AC", "sparkles": "#C79BFF",
    "clock.arrow.circlepath": "#7FD8F0", "paw": "#76D98F",
}

UNIT = 64
SUPER = 8
INSET = 0.70


def render_icon(fn, color, size):
    canvas = UNIT * SUPER
    inner = int(canvas * INSET)
    glyph = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    d = ImageDraw.Draw(glyph)
    fn(d, 0, 0, inner, color, int(canvas / UNIT * 5))
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    off = (canvas - inner) // 2
    img.paste(glyph, (off, off), glyph)
    return img.resize((size, size), Image.LANCZOS)


def rgba(hex_color, alpha):
    r, g, b = dark.hexc(hex_color)
    return f"rgba({r}, {g}, {b}, {alpha})"


def build_css():
    md = P["md"]
    lines = [
        "/* FOREST NIGHT · 深林夜：墨绿底 + 苔藓绿，松林深处的夜色。纯色，无渐变。",
        "   暗色单主题：dawn / night 两侧都是这套夜森林。 */",
        ":root,",
        ':root[data-theme="dawn"],',
        ':root[data-theme="night"] {',
        f'  --bg: {P["bg"]};',
        f'  --surface: {P["surface"]};',
        f'  --text: {P["text"]};',
        f'  --text-secondary: {P["--text-secondary"]};',
        f'  --border: {rgba(P["text"], 0.14)};',
        f'  --border-strong: {rgba(P["text"], 0.26)};',
        f'  --accent: {P["accent"]};',
        f'  --accent-ink: {P["accent_ink"]};',
        f'  --accent-soft: {rgba(P["accent"], 0.16)};',
        f'  --code-bg: {P["code_bg"]};',
        f'  --code-border: {rgba(P["text"], 0.12)};',
        f'  --code-text: {P["text"]};',
        f'  --note: {P["note"]};   --note-bg: {rgba(P["note"], 0.14)};',
        f'  --tip: {P["tip"]};    --tip-bg: {rgba(P["tip"], 0.14)};',
        f'  --warn: {P["warn"]};   --warn-bg: {rgba(P["warn"], 0.16)};',
        f'  --danger: {P["danger"]}; --danger-bg: {rgba(P["danger"], 0.14)};',
        f'  --info: {P["info"]};   --info-bg: {rgba(P["info"], 0.14)};',
        f'  --muted: {P["secondary"]};',
        f'  --hl-kw: {P["hl_kw"]}; --hl-str: {P["hl_str"]}; --hl-num: {P["hl_num"]};',
        f'  --hl-comment: {P["hl_comment"]}; --hl-type: {md["h2"]}; --hl-func: {md["callout"]};',
        f'  --hl-tag: {md["bold"]}; --hl-attr: {md["italic"]};',
        "}",
        "",
        "body {",
        '  font-family: "Hiragino Sans GB", "PingFang SC", -apple-system, sans-serif;',
        "}",
        ".markdown-body h1,",
        ".markdown-body h2,",
        ".markdown-body h3,",
        ".markdown-body h4 {",
        '  font-family: "Ma Shan Zheng", "Songti SC", serif;',
        "  font-weight: 400;",
        "}",
        ".markdown-body code,",
        ".markdown-body pre,",
        ".codefile code {",
        '  font-family: "JetBrains Mono", "SF Mono", monospace !important;',
        "}",
        ".markdown-body a,",
        ".footnote-ref a,",
        ".footnote-backref {",
        "  color: var(--accent-ink, var(--accent));",
        "}",
        "",
        "/* 多彩钩子：标题 / 加粗 / 斜体各一色相（同明度带，保持和谐） */",
        ":root {",
        f'  --h1: {md["h1"]};',
        f'  --h2: {md["h2"]};',
        f'  --h3: {md["h3"]};',
        f'  --strong: {md["bold"]};',
        f'  --em: {md["italic"]};',
        f'  --hr: {rgba(md["hr"], 0.55)};',
        "}",
        "",
        "/* 编辑器 Markdown 语法色（auditVersion 5 必填，33 项）",
        "   标记中性、内容分色；列表 / 序号 / 任务用可见色（彩度 ≥12）。 */",
        ":root {",
    ]
    order = ["h1", "h2", "h3", "bold", "italic", "code", "link", "quote", "math",
             "highlight", "strike", "insert", "callout", "table-head", "embed", "kbd",
             "mention", "emoji", "badge", "timeline", "term", "mermaid",
             "list", "number", "task", "marker", "url", "hr", "table", "fence", "html"]
    for key in order:
        lines.append(f"  --md-{key}: {md[key]};")
    lines.append(f'  --md-code-bg: {P["code_bg"]};')
    lines.append(f'  --md-highlight-bg: {rgba(md["highlight"], 0.20)};')
    lines.append("}")
    return "\n".join(lines) + "\n"


ENTRY = dict(
    id="forest-night",
    name="深林夜",
    desc="松林深处的夜色：墨绿底 + 苔藓绿，楷书标题、多色植物图标、叶片光尘与萤火彩蛋",
    reviewed=False,
    auditVersion=5,
    cssFile="theme.css",
    swatchHex=P["accent"],
    displayFont={"file": "fonts/MaShanZheng-Regular.ttf", "family": "Ma Shan Zheng", "size": 18},
    codeFont={"file": "fonts/JetBrainsMono.ttf", "family": "JetBrains Mono", "size": 13},
    icons={},
    easterEgg=dict(trigger="icon-click", clicks=5,
                   symbols=["✨", "🌟", "·", "✧"], message="夜深了"),
    motion=dict(ambientPollen=True, iconBounce=True, tabSpring=True,
                durationMs=260, respectReduceMotion=True),
    glass=0,
)

MANIFEST = dict(
    id="theme-forest-night", name="深林夜", nameEn="Forest Night", version="1.0.0", kind="theme",
    desc="暗色单主题：墨绿底 + 苔藓绿，楷书标题、19 个多色语义图标、叶片光尘与萤火彩蛋",
    descEn="Dark-only forest theme with moss accent, calligraphic display font, 19 multi-hue semantic icons, drifting leaves and a firefly easter egg",
    features=[
        "暗色单主题：纸底 #0E1512（亮度 <0.2），不做半成品灰调",
        "19 个语义图标按文件类型分色（暗底提亮，同明度带），透明字形无底板，14px 可辨",
        "专属字体：马善政楷书标题 + JetBrains Mono 编辑字体",
        "33 个编辑器语法色：标记中性、内容分色，列表 / 序号 / 任务用可见色",
        "叶片光尘氛围 + 图标签弹跳 + 页签弹簧；连点图标 5 次 → 萤火 +「夜深了」",
    ],
    featuresEn=[
        "Dark-only palette (#0E1512, luminance <0.2)",
        "19 multi-hue semantic icons, transparent glyphs, readable at 14px",
        "Bundled fonts: Ma Shan Zheng display + JetBrains Mono for the editor",
        "33 editor syntax colours; markers stay quiet, lists stay visible",
        "Drifting leaves, icon bounce, tab spring; click the icon 5× for fireflies",
    ],
    author="随手社区", main="theme.json", minAppVersion="1.8.0", icon="leaf",
)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "plugins-market/_review/theme-forest-night-v1"
    out.mkdir(parents=True, exist_ok=True)
    (out / "icons").mkdir(exist_ok=True)
    (out / "fonts").mkdir(exist_ok=True)

    src_fonts = ROOT / "plugins-market/theme-sumi-paper/fonts"
    for name in ("MaShanZheng-Regular.ttf", "JetBrainsMono.ttf",
                 "OFL-MaShanZheng.txt", "OFL-JetBrainsMono.txt"):
        shutil.copy2(src_fonts / name, out / "fonts" / name)

    mt = _load("make-misty-teal")
    coverage = []
    for key, fname, fn, _tier in mt.ICON_MAP:
        color = ICON_HUES[key]
        render_icon(fn, color, 256).save(out / f"icons/{fname}-256.png")
        small = render_icon(fn, color, 64)
        small.save(out / f"icons/{fname}-64.png")
        px = small.convert("RGBA").resize((64, 64)).getdata()
        cov = sum(1 for r, g, b, a in px if a > 38) / len(px)
        coverage.append((key, fname, cov, color))

    (out / "theme.css").write_text(build_css(), encoding="utf-8")
    entry = json.loads(json.dumps(ENTRY))
    for key, fname, _cov, _color in coverage:
        entry["icons"][key] = f"icons/{fname}-64.png"
    (out / "theme.json").write_text(json.dumps([entry], ensure_ascii=False, indent=2) + "\n",
                                    encoding="utf-8")
    (out / "manifest.json").write_text(json.dumps(MANIFEST, ensure_ascii=False, indent=2) + "\n",
                                       encoding="utf-8")
    (out / "README.md").write_text(README, encoding="utf-8")

    print(f"包目录: {out}")
    print(f"纸底 {P['bg']}（亮度 {dark.lum(P['bg']):.3f}）  主色 {P['accent']}  强调文字 {P['accent_ink']}")
    print(f"实测：正文 {METRICS['text']:.2f} 次级 {METRICS['secondary']:.2f} 主色 {METRICS['accent']:.2f} "
          f"高亮 {METRICS['hl']:.2f} 提示 {METRICS['callout']:.2f} 内容 {METRICS['content_contrast']:.2f} "
          f"| ΔE 主色 {METRICS['core']:.0f} 内容 {METRICS['content']:.0f} "
          f"| 标记彩度 {METRICS['marker_chroma']:.0f} 列表彩度 {METRICS['visible_chroma']:.0f}")
    print("图标覆盖率：" + "，".join(f"{k} {c*100:.0f}%" for k, _f, c, _c in coverage[:5]) + " …")


README = """# 深林夜 · Forest Night

松林深处的夜色：墨绿底 + 苔藓绿主色；暗色单主题（dawn / night 两侧都是这套夜森林）。

## 专属资产

- 字体：标题 `Ma Shan Zheng`（马善政楷书，OFL）；编辑 / 行号 `JetBrains Mono`（OFL）；正文沿用系统苹方。
- 图标：19 个语义槽位，按文件类型分色（暗底提亮、同明度带），透明字形无底板，14px 可辨。
- 动效：`ambientPollen` 叶片光尘漂落 + 图标弹跳 + 页签弹簧，全部尊重系统「减少动态效果」。
- 彩蛋：连点彩蛋图标 5 次 → 萤火 +「夜深了」。

## 配色

| 角色 | 值 |
| --- | --- |
| 纸底 / 面板 | `#0E1512` / `#141D18` |
| 正文 / 次级 | `#E8F0EA` / `#9CB3A6` |
| 主色 / 主色文字 | `#3FD1A5` / `#6FDDB4` |
| 多彩钩子 | 标题 `#3FD1A5` / `#7FD8F0` / `#B49BFF`，加粗 `#FF9E9E`，斜体 `#FFD479` |

实测：正文 15.94:1、次级 8.30:1、主色文字 11.17:1、代码高亮 5.40:1、提示色 8.44:1；
ΔE 主色 29、内容 14；标记彩度 11、列表彩度 29 —— 全部高于 v5 门槛。
"""


if __name__ == "__main__":
    main()
