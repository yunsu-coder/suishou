#!/usr/bin/env python3
"""生成「雾青」亮色主题包（评审稿）：B3 原样配色 + P1 字体配对 + 19 个专属语义图标。

用法: python3 scripts/make-misty-teal.py [输出目录]
默认输出: plugins-market/_review/theme-misty-teal-v1
"""

import importlib.util
import json
import shutil
import sys
from pathlib import Path
from string import Template

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent


def _load(name):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


b3 = _load("make-garden-b3")

# ---------------------------------------------------------------- 配色（B3 原样）

P = dict(
    bg="#F5F7F3",           # 编辑纸
    surface="#FFFFFF",      # 卡片 / 预览底
    rail="#E9EDE9",         # 图标栏
    sidebar="#EEF1ED",      # 侧栏
    status="#E6EBE7",
    line="#D3DAD4",
    card="#FFFFFF",
    card2="#F1F4F0",
    sel="#DCE8E1",
    text="#25302B",
    text2="#4C5C55",
    secondary="#6C7A73",
    muted="#8A948D",
    accent="#3C7867",
    accent_ink="#33695A",
    accent2="#A98BB2",
    aux="#C9A227",
)

TIERS = {
    "folder": "#2C5F52",
    "doc": "#3C7867",
    "other": "#8A948D",
    "accent2": P["accent2"],
}

# 供渲染稿复用的图标分级键（与 theme.json 中的三档颜色一致）
P["icon.folder"] = TIERS["folder"]
P["icon.doc"] = TIERS["doc"]
P["icon.other"] = TIERS["other"]
# 供渲染稿复用的别名（评审图沿用同一套色板）
P["dim"] = P["secondary"]
P["ink"] = P["text"]
P["paper"] = P["surface"]

# key → (文件名, 画法, 颜色档)
ICON_MAP = [
    ("folder", "folder", b3.g_pot, "folder"),
    ("folder.open", "folder.open", lambda d, x, y, s, c, lw: b3.g_pot(d, x, y, s, c, lw, True), "folder"),
    ("file.markdown", "file.markdown", b3.g_leaf, "doc"),
    ("file.code", "file.code", b3.g_trellis, "doc"),
    ("file.data", "file.data", b3.g_seedtray, "other"),
    ("file.image", "file.image", b3.g_frame, "other"),
    ("file.video", "file.video", b3.g_film, "other"),
    ("file.audio", "file.audio", b3.g_bell, "other"),
    ("file.document", "file.document", b3.g_scroll, "doc"),
    ("file.archive", "file.archive", b3.g_jar, "other"),
    ("file.other", "file.other", b3.g_page, "other"),
    ("puzzlepiece.extension", "plugin", b3.g_graft, "doc"),
    ("shippingbox", "box", b3.g_crate, "other"),
    ("gearshape", "settings", b3.g_gear, "other"),
    ("sidebar.left", "sidebar", b3.g_window, "other"),
    ("magnifyingglass", "search", b3.g_lens, "other"),
    ("sparkles", "sparkle", b3.g_sparkle, "accent2"),
    ("clock.arrow.circlepath", "history", b3.g_sundial, "other"),
    ("paw", "paw", b3.g_paw, "accent2"),
]

UNIT = 64   # 逻辑尺寸：所有图标按 64×64 坐标绘制
SUPER = 8   # 8× 超采样，保证 14px 下笔画干净
INSET = 0.70  # 字形占画布比例：与其它主题的视觉重量对齐（文件树 14px 时约 9.8px）


def render_icon(fn, color, size):
    canvas = UNIT * SUPER
    inner = int(canvas * INSET)
    glyph = Image.new("RGBA", (inner, inner), (0, 0, 0, 0))
    from PIL import ImageDraw
    d = ImageDraw.Draw(glyph)
    fn(d, 0, 0, inner, color, int(canvas / UNIT * 5))    # 5px 笔画 @64，配合内缩后的小字形
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    off = (canvas - inner) // 2
    img.paste(glyph, (off, off), glyph)
    return img.resize((size, size), Image.LANCZOS)


def coverage(img):
    px = img.convert("RGBA").resize((64, 64))
    data = px.getdata()
    opaque = sum(1 for r, g, b, a in data if a > 38)
    return opaque / len(data)


# ---------------------------------------------------------------- CSS

CSS = """/* MISTY TEAL · 雾青：纸感亮色 + 青瓷主色。纯色，无渐变。
   亮色单主题：dawn / night 两个变体指向同一套纸色，选哪侧都保持同一外观。 */
:root,
:root[data-theme="dawn"],
:root[data-theme="night"] {
  --bg: $bg;
  --surface: $surface;
  --text: $text;
  --text-secondary: $secondary;
  --border: rgba(37, 48, 43, 0.16);
  --border-strong: rgba(37, 48, 43, 0.30);
  --accent: $accent;
  --accent-ink: $accent_ink;
  --accent-soft: rgba(60, 120, 103, 0.12);
  --code-bg: $card2;
  --code-border: rgba(37, 48, 43, 0.14);
  --code-text: $text;
  --note: #3A6B8A;   --note-bg: rgba(58, 107, 138, 0.10);
  --tip: #33705F;    --tip-bg: rgba(51, 112, 95, 0.10);
  --warn: #8A6A1F;   --warn-bg: rgba(138, 106, 31, 0.12);
  --danger: #A8443A; --danger-bg: rgba(168, 68, 58, 0.10);
  --info: #3A6B8A;   --info-bg: rgba(58, 107, 138, 0.10);
  --muted: $muted;
  --hl-kw: #2F6E5D; --hl-str: #7A5F8A; --hl-num: #8A6A1F;
  --hl-comment: #7E8A83; --hl-type: #3A6B8A; --hl-func: #8A6A1F;
  --hl-tag: #A8443A; --hl-attr: #6B5A2F;
}

body {
  font-family: "Hiragino Sans GB", "PingFang SC", -apple-system, sans-serif;
}
.markdown-body h1,
.markdown-body h2,
.markdown-body h3,
.markdown-body h4 {
  font-family: "站酷小薇体", "Songti SC", serif;
  font-weight: 400;
}
.markdown-body code,
.markdown-body pre,
.codefile code {
  font-family: "JetBrains Mono", "SF Mono", monospace !important;
}
.markdown-body a,
.footnote-ref a,
.footnote-backref {
  color: var(--accent-ink, var(--accent));
}
"""


def hex_to_rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


def lum(h):
    r, g, b = (c / 255 for c in hex_to_rgb(h))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


THEME_ENTRY = {
    "id": "misty-teal",
    "name": "雾青",
    "desc": "纸感亮色 + 青瓷主色；植物语义图标、叶片光尘动效与开花彩蛋",
    "reviewed": False,
    "auditVersion": 4,
    "cssFile": "theme.css",
    "swatchHex": P["accent"],
    "displayFont": {"file": "fonts/ZCOOLXiaoWei-Regular.ttf", "family": "站酷小薇体", "size": 18},
    "codeFont": {"file": "fonts/JetBrainsMono.ttf", "family": "JetBrains Mono", "size": 13},
    "icons": {},
    "easterEgg": {
        "trigger": "icon-click",
        "clicks": 5,
        "symbols": ["❀", "✿", "❁", "✧"],
        "message": "花开",
    },
    "motion": {
        "ambientPollen": True,
        "iconBounce": True,
        "tabSpring": True,
        "durationMs": 260,
        "respectReduceMotion": True,
    },
    "glass": 0,
}

MANIFEST = {
    "id": "theme-misty-teal",
    "name": "雾青",
    "nameEn": "Misty Teal",
    "version": "1.0.0",
    "kind": "theme",
    "desc": "纸感亮色主题：青瓷主色、植物语义图标、叶片光尘动效与开花彩蛋；只做亮色一套",
    "descEn": "Light-only paper theme with celadon accent, botanical semantic icons, drifting pollen motion and a bloom easter egg",
    "features": [
        "亮色单主题：选任何一侧都保持同一套纸色，不做半成品暗色混搭",
        "19 个语义图标（花盆 / 叶片 / 藤架 / 种子罐…），透明字形无底板，14px 可辨",
        "专属字体：站酷小薇标题 + JetBrains Mono 编辑字体",
        "叶片光尘氛围 + 图标签弹跳 + 页签弹簧；连点图标 5 次开花",
    ],
    "featuresEn": [
        "Light-only palette, identical on both variants — no half-finished dark mix",
        "19 botanical semantic icons, transparent glyphs with no plates, readable at 14px",
        "Bundled fonts: ZCOOL XiaoWei display + JetBrains Mono for the editor",
        "Drifting pollen ambience, icon bounce, tab spring; click the icon 5× to bloom",
    ],
    "author": "随手社区",
    "main": "theme.json",
    "minAppVersion": "1.8.0",
    "icon": "leaf",
}


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "plugins-market/_review/theme-misty-teal-v1"
    out.mkdir(parents=True, exist_ok=True)
    (out / "icons").mkdir(exist_ok=True)
    (out / "fonts").mkdir(exist_ok=True)

    # 字体（P1）：站酷小薇标题 + JetBrains Mono 编辑字体
    src_fonts = ROOT / "plugins-market/theme-sumi-paper/fonts"
    for name in ("ZCOOLXiaoWei-Regular.ttf", "JetBrainsMono.ttf",
                 "OFL-ZCOOLXiaoWei.txt", "OFL-JetBrainsMono.txt"):
        shutil.copy2(src_fonts / name, out / "fonts" / name)

    # 图标
    report = []
    entry = json.loads(json.dumps(THEME_ENTRY))
    for key, fname, fn, tier in ICON_MAP:
        color = TIERS[tier]
        big = render_icon(fn, color, 256)
        small = render_icon(fn, color, 64)
        big.save(out / f"icons/{fname}-256.png")
        small.save(out / f"icons/{fname}-64.png")
        entry["icons"][key] = f"icons/{fname}-64.png"
        report.append((key, fname, coverage(small), color))

    (out / "theme.css").write_text(Template(CSS).substitute(P), encoding="utf-8")
    (out / "theme.json").write_text(
        json.dumps([entry], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "manifest.json").write_text(
        json.dumps(MANIFEST, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "README.md").write_text(README, encoding="utf-8")

    print(f"包目录: {out}")
    print("—— 可读性 ——")
    for label, fg, bg, need in [
        ("正文 / 纸", P["text"], P["bg"], 4.5),
        ("次级 / 纸", P["secondary"], P["bg"], 3.5),
        ("强调 / 纸", P["accent_ink"], P["bg"], 4.0),
        ("正文 / 选中行", P["text"], P["sel"], 4.5),
        ("正文 / 代码底", P["text"], P["card2"], 4.5),
    ]:
        r = contrast(fg, bg)
        print(f"  {label:<10} {r:5.2f}:1  需 ≥{need}  {'OK' if r >= need else 'FAIL'}")
    print("—— 图标 ——")
    for key, fname, cov, color in report:
        flag = "OK" if cov <= 0.82 else "FAIL(底板?)"
        print(f"  {key:<26} {fname}-64.png 覆盖 {cov * 100:4.1f}%  {color}  {flag}")


README = """# 雾青 · Misty Teal（亮色主题）

纸感亮色 + 青瓷主色，只做亮色一套：`dawn` / `night` 两个变体指向同一套纸色，
菜单里选哪一侧都是同一外观，不会出现「亮色纸 + 暗色控件」的混搭。

## 专属资产

- 字体：标题 `ZCOOL XiaoWei`（站酷小薇，OFL）；编辑 / 行号 `JetBrains Mono`（OFL）；
  正文与界面沿用系统苹方（0 MB）。
- 图标：19 个语义槽位，全部为透明字形、无底板，14px 文件树尺寸可辨；
  颜色分三档 —— 容器 `#2C5F52`、文档 `#3C7867`、其他格式 `#8A948D`，主题 / 彩蛋用 `#A98BB2`。
- 动效：`ambientPollen` 叶片光尘缓慢飘落 + 图标弹跳 + 页签弹簧，全部尊重系统「减少动态效果」。
- 彩蛋：连点彩蛋图标 5 次 → 花瓣雨 + 「花开」。

## 配色

| 角色 | 值 |
| --- | --- |
| 编辑纸 | `#F5F7F3` |
| 侧栏 / 图标栏 | `#EEF1ED` / `#E9EDE9` |
| 正文 / 次级 | `#25302B` / `#6C7A73` |
| 主色 / 主色文字 | `#3C7867` / `#33695A` |
| 强调（仅开花、里程碑） | `#A98BB2` |
| 点缀 | `#C9A227` |

对比度：正文 12.68:1、次级 4.17:1、强调 4.78:1，全部高于硬门槛。
"""


if __name__ == "__main__":
    main()
