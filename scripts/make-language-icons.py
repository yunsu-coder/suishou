#!/usr/bin/env python3
"""每个语言一个专属图标 —— 四个主题各自用自己的工艺画（评审稿）。

工艺对齐各主题现有图标：
- sumi-paper  墨纸：朱砂/墨线笔画字母（Ma Shan Zheng），角落一点朱砂落款
- bubble-pop  像素糖果：3x5 点阵字母 + 三色立体（亮面/本色/暗面）
- forest-night 深林夜：JetBrains Mono 描粗的霓虹字（每语言一个色相，透明底）
- misty-teal   雾青：与深林夜同一套字形，换亮色主题的深调色（两个主题是姊妹）

用法:
  python3 scripts/make-language-icons.py            # 生成评审稿到 plugins-market/_review/lang-icons
  python3 scripts/make-language-icons.py --install  # 审核通过后写入四个主题包（并升版本）
"""

import os
import subprocess
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
MARKET = ROOT / "plugins-market"
REVIEW = MARKET / "_review" / "lang-icons"
S = 4                                    # 超采样
UNIT = 64

# 评审图上的中文说明（系统自带中文字体）
UI_FONT = "/System/Library/Fonts/STHeiti Medium.ttc"

FONTS = {
    "brush": MARKET / "theme-sumi-paper/fonts/MaShanZheng-Regular.ttf",
    "pixel": MARKET / "theme-bubble-pop/fonts/FusionPixel12pxMonospacedSC.ttf",
    "mono": MARKET / "theme-forest-night/fonts/JetBrainsMono.ttf",
}

# 语言槽位：key = 主题图标名（与 Workspace.themeIconKey 对齐），mono = 图标上的字样
LANGUAGES = [
    ("file.python", "PY"),
    ("file.javascript", "JS"),
    ("file.typescript", "TS"),
    ("file.go", "GO"),
    ("file.rust", "RS"),
    ("file.c", "C"),
    ("file.cpp", "C+"),
    ("file.csharp", "C#"),
    ("file.java", "JV"),
    ("file.kotlin", "KT"),
    ("file.swift", "SW"),
    ("file.html", "<>"),
    ("file.css", "{}"),
    ("file.xml", "X"),
    ("file.vue", "V"),
    ("file.shell", "$"),
    ("file.json", "[]"),
    ("file.yaml", "Y"),
    ("file.sql", "DB"),
    ("file.ruby", "RB"),
    ("file.php", "PH"),
    ("file.lua", "LU"),
    ("file.asm", "AS"),
    ("file.r", "R"),
]

# 每个主题一套语言色（与该主题已有色板同一明度带）
COLORS = {
    "theme-sumi-paper": {
        "file.python": "#3B5BA5", "file.javascript": "#B8860B", "file.typescript": "#2F6FA8",
        "file.go": "#2F7FA0", "file.rust": "#B4552A", "file.c": "#4A6FA5",
        "file.cpp": "#5B3FD6", "file.csharp": "#7A3FBF", "file.java": "#B5452F",
        "file.kotlin": "#8A3FD6", "file.swift": "#C4552A", "file.html": "#C8442E",
        "file.css": "#2F6FA8", "file.xml": "#6B6257", "file.vue": "#2F8757",
        "file.shell": "#3F6B4F", "file.json": "#8A6A2E", "file.yaml": "#B03A6E",
        "file.sql": "#2F7A78", "file.ruby": "#C8442E", "file.php": "#5B3FBF",
        "file.lua": "#2F4F9E", "file.asm": "#6F6A63", "file.r": "#3B5BA5",
    },
    "theme-bubble-pop": {
        "file.python": "#4FB8FF", "file.javascript": "#FFD23C", "file.typescript": "#5B8CFF",
        "file.go": "#43C6D8", "file.rust": "#FF8A5C", "file.c": "#6E9BE8",
        "file.cpp": "#5B31D6", "file.csharp": "#9A6BFF", "file.java": "#FF7A5C",
        "file.kotlin": "#B06BFF", "file.swift": "#FF9A3C", "file.html": "#FF7A3C",
        "file.css": "#4FB8FF", "file.xml": "#9AA0AC", "file.vue": "#3ECFA0",
        "file.shell": "#4FD1A5", "file.json": "#FFC93C", "file.yaml": "#FF7AB6",
        "file.sql": "#43D1C0", "file.ruby": "#FF5C7A", "file.php": "#7C4DFF",
        "file.lua": "#3C6BFF", "file.asm": "#9AA0AC", "file.r": "#4FB8FF",
    },
    "theme-forest-night": {
        "file.python": "#7FD8F0", "file.javascript": "#E8D06A", "file.typescript": "#86B4FF",
        "file.go": "#5FD3E0", "file.rust": "#E8955A", "file.c": "#9CC2FF",
        "file.cpp": "#B49BFF", "file.csharp": "#C79BFF", "file.java": "#FF9E8A",
        "file.kotlin": "#D0A6FF", "file.swift": "#FFB37A", "file.html": "#FF9E7A",
        "file.css": "#86B4FF", "file.xml": "#A8B8AC", "file.vue": "#76D98F",
        "file.shell": "#76D98F", "file.json": "#E8D06A", "file.yaml": "#FF9ED8",
        "file.sql": "#7FD8C0", "file.ruby": "#FF8A9E", "file.php": "#A6A0FF",
        "file.lua": "#8FA8FF", "file.asm": "#8FA79A", "file.r": "#7FD8F0",
    },
    "theme-misty-teal": {
        "file.python": "#2C6E82", "file.javascript": "#8A6B12", "file.typescript": "#2F5F9E",
        "file.go": "#2A7C86", "file.rust": "#A8552A", "file.c": "#3C6291",
        "file.cpp": "#5B3FA8", "file.csharp": "#6E43A8", "file.java": "#A8422C",
        "file.kotlin": "#7A3FB0", "file.swift": "#B45A22", "file.html": "#B2432A",
        "file.css": "#2F5F9E", "file.xml": "#6C7A73", "file.vue": "#2C6F4E",
        "file.shell": "#2C6F4E", "file.json": "#7A5F12", "file.yaml": "#9E3A61",
        "file.sql": "#2A6E6C", "file.ruby": "#A83A3A", "file.php": "#4A4FA8",
        "file.lua": "#2F4A8A", "file.asm": "#6C7A73", "file.r": "#2C6E82",
    },
}

# ─────────────────────────────────────────────── 3x5 点阵（像素主题用）

FONT3x5 = {
    "A": [".#.", "#.#", "###", "#.#", "#.#"],
    "B": ["##.", "#.#", "##.", "#.#", "##."],
    "C": [".##", "#..", "#..", "#..", ".##"],
    "D": ["##.", "#.#", "#.#", "#.#", "##."],
    "E": ["###", "#..", "##.", "#..", "###"],
    "G": [".##", "#..", "#.#", "#.#", ".##"],
    "H": ["#.#", "#.#", "###", "#.#", "#.#"],
    "J": ["..#", "..#", "..#", "#.#", ".#."],
    "K": ["#.#", "#.#", "##.", "#.#", "#.#"],
    "L": ["#..", "#..", "#..", "#..", "###"],
    "M": ["#.#", "###", "###", "#.#", "#.#"],
    "O": [".#.", "#.#", "#.#", "#.#", ".#."],
    "P": ["##.", "#.#", "##.", "#..", "#.."],
    "R": ["##.", "#.#", "##.", "#.#", "#.#"],
    "S": [".##", "#..", ".#.", "..#", "##."],
    "T": ["###", ".#.", ".#.", ".#.", ".#."],
    "U": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "V": ["#.#", "#.#", "#.#", "#.#", ".#."],
    "W": ["#.#", "#.#", "###", "###", "#.#"],
    "X": ["#.#", "#.#", ".#.", "#.#", "#.#"],
    "Y": ["#.#", "#.#", ".#.", ".#.", ".#."],
    "+": ["...", ".#.", "###", ".#.", "..."],
    "#": [".#.", "###", ".#.", "###", ".#."],
    "<": ["..#", ".#.", "#..", ".#.", "..#"],
    ">": ["#..", ".#.", "..#", ".#.", "#.."],
    "{": ["..##", ".#..", "##..", ".#..", "..##"],
    "}": ["##..", "..#.", "..##", "..#.", "##.."],
    "[": ["##", "#.", "#.", "#.", "##"],
    "]": ["##", ".#", ".#", ".#", "##"],
    "$": ["..#", ".###", "###.", "###.", "#.."],
    " ": ["..", "..", "..", "..", ".."],
}


def pixel_glyph(text):
    """2 个 3x5 字符 → 8x8 点阵（每行 8 列）"""
    chars = [c for c in text.upper()][:2]
    while len(chars) < 2:
        chars.append(" ")
    rows = []
    for r in range(5):
        row = ""
        for i, ch in enumerate(chars):
            pat = FONT3x5.get(ch, FONT3x5[" "])
            row += pat[r].ljust(3, ".")
            if i == 0:
                row += "."
        rows.append(row.ljust(8, ".")[:8])
    return ["........"] + rows + ["........", "........"]   # 上下留白


def shade(hex_color, factor):
    r = int(hex_color[1:3], 16); g = int(hex_color[3:5], 16); b = int(hex_color[5:7], 16)
    f = lambda v: max(0, min(255, int(v * factor)))
    return f"#{f(r):02X}{f(g):02X}{f(b):02X}"


# ─────────────────────────────────────────────── 各主题渲染

def render_sumi(mono, color):
    """墨纸：透明墨线字（与 file.* 同工艺：无底板、只用笔画）+ 角上一点朱砂"""
    canvas = UNIT * S
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(FONTS["mono"]), int(canvas * 0.42))
    while d.textlength(mono, font=font) > canvas * 0.68 and font.size > 8:
        font = ImageFont.truetype(str(FONTS["mono"]), font.size - 2)
    d.text((canvas / 2, canvas / 2 - canvas * 0.02), mono, font=font, fill=color, anchor="mm",
           stroke_width=int(canvas * 0.016), stroke_fill=color)
    d.ellipse([canvas * 0.70, canvas * 0.10, canvas * 0.85, canvas * 0.25], fill="#C8442E")
    return img


def render_pixel(mono, color):
    """像素糖果：三色立体的 8x8 点阵"""
    canvas = UNIT * S
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    grid = pixel_glyph(mono)
    cell = canvas // 8
    light = shade(color, 1.35)
    dark = shade(color, 0.72)
    for r in range(8):
        for c in range(8):
            if grid[r][c] != "#":
                continue
            x, y = c * cell, r * cell
            d.rectangle([x, y, x + cell - 1, y + cell - 1], fill=color)
            # 顶面提亮 / 底面压暗：只描外轮廓那一条，避免整块发花
            if r == 0 or grid[r - 1][c] != "#":
                d.rectangle([x, y, x + cell - 1, y + max(1, cell // 4) - 1], fill=light)
            if r == 7 or grid[r + 1][c] != "#":
                d.rectangle([x, y + cell - max(1, cell // 4), x + cell - 1, y + cell - 1], fill=dark)
    return img


def render_line(mono, color):
    """深色/亮色线描主题：描粗的单色字（每语言一个色相）"""
    canvas = UNIT * S
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    size = int(canvas * 0.46) if len(mono) == 1 else int(canvas * 0.40)
    font = ImageFont.truetype(str(FONTS["mono"]), size)
    while d.textlength(mono, font=font) > canvas * 0.74 and size > 8:
        size -= 2
        font = ImageFont.truetype(str(FONTS["mono"]), size)
    d.text((canvas / 2, canvas / 2), mono, font=font, fill=color, anchor="mm",
           stroke_width=int(canvas * 0.022), stroke_fill=color)
    return img


RENDER = {
    "theme-sumi-paper": render_sumi,
    "theme-bubble-pop": render_pixel,
    "theme-forest-night": render_line,
    "theme-misty-teal": render_line,
}


def build(out_root: Path, only_preview=False):
    made = {}
    for theme, fn in RENDER.items():
        colors = COLORS[theme]
        target = out_root / theme
        target.mkdir(parents=True, exist_ok=True)
        for key, mono in LANGUAGES:
            img = fn(mono, colors[key])
            img.resize((64, 64), Image.LANCZOS).save(target / f"{key}-64.png")
            img.resize((256, 256), Image.LANCZOS).save(target / f"{key}-256.png")
        made[theme] = target
    return made


def preview_sheet(made, out_path: Path):
    themes = list(RENDER.keys())
    cols = len(LANGUAGES)
    cell, label_w, row_h = 56, 132, 74
    W = label_w + cols * cell + 16
    H = 54 + len(themes) * row_h * 2 + 26 + 300
    sheet = Image.new("RGB", (W, H), "#FFFFFF")
    d = ImageDraw.Draw(sheet)
    ui = ImageFont.truetype(UI_FONT, 12)
    small = ImageFont.truetype(UI_FONT, 9)
    d.text((12, 14), "LANGUAGE ICONS · 每语言专属图标（上：64px 实际显示 / 下：16px 侧栏实际大小）",
           font=ui, fill="#111111")
    y = 44
    for theme in themes:
        d.text((12, y + 18), theme.replace("theme-", ""), font=ui, fill="#333333")
        big = y + 4
        tiny = y + 38
        for i, (key, _) in enumerate(LANGUAGES):
            x = label_w + i * cell
            im = Image.open(made[theme] / f"{key}-64.png").convert("RGBA").resize((48, 48), Image.LANCZOS)
            sheet.paste(im, (x + 4, big), im)
            im2 = Image.open(made[theme] / f"{key}-64.png").convert("RGBA").resize((16, 16), Image.LANCZOS)
            sheet.paste(im2, (x + 20, tiny + 8), im2)
        y += row_h * 2
    tree_mock(sheet, themes, made, y0=y + 6)
    sheet.save(out_path)
    return out_path


def tree_mock(sheet, themes, made, y0):
    """真实侧栏大小：把新图标放进文件树（明暗两个主题各一棵）"""
    d = ImageDraw.Draw(sheet)
    ui = ImageFont.truetype(UI_FONT, 12)
    name = ImageFont.truetype(str(FONTS["mono"]), 12)
    d.text((12, y0), "侧栏实况（16px + 文件名，真实行高 24px）", font=ui, fill="#111111")
    rows = [("file.python", "collector.py"), ("file.javascript", "app.js"),
            ("file.typescript", "types.ts"), ("file.go", "main.go"),
            ("file.cpp", "1.cpp"), ("file.css", "theme.css"),
            ("file.html", "index.html"), ("file.json", "package.json")]
    y = y0 + 22
    for theme in ["theme-forest-night", "theme-misty-teal"]:
        dark = theme == "theme-forest-night"
        bg = "#141812" if dark else "#F5F7F3"
        fg = "#DDE3DC" if dark else "#25302B"
        box_w, box_h = 300, len(rows) * 24 + 44
        x = 12 if theme == "theme-forest-night" else 330
        d.rounded_rectangle([x, y, x + box_w, y + box_h], radius=8, fill=bg)
        d.text((x + 12, y + 10), theme.replace("theme-", ""), font=ui, fill=fg)
        for i, (key, label) in enumerate(rows):
            ry = y + 36 + i * 24
            if key == "file.cpp":
                d.rounded_rectangle([x + 6, ry - 2, x + box_w - 6, ry + 20], radius=5,
                                    fill="#3A4A3E" if dark else "#DCE8E1")
            im = Image.open(made[theme] / f"{key}-64.png").convert("RGBA").resize((16, 16), Image.LANCZOS)
            sheet.paste(im, (x + 14, ry + 1), im)
            d.text((x + 36, ry + 3), label, font=name, fill=fg)
    d.text((12, y + len(rows) * 24 + 60), "（16px 下仍可区分：字母形状 + 语言色相双重编码）",
           font=ui, fill="#777777")


def main():
    install = "--install" in sys.argv
    if install:
        # 审核通过：写进主题包 + 在 theme.json 里声明槽位 + 升版本（auditVersion 5 → 6，语言图标整组必填）
        import json
        for theme, fn in RENDER.items():
            colors = COLORS[theme]
            pkg = MARKET / theme
            icons = pkg / "icons"
            for key, mono in LANGUAGES:
                img = fn(mono, colors[key])
                img.resize((64, 64), Image.LANCZOS).save(icons / f"{key}-64.png")
                img.resize((256, 256), Image.LANCZOS).save(icons / f"{key}-256.png")

            spec_path = pkg / "theme.json"
            spec = json.loads(spec_path.read_text())
            for t in spec:
                t.setdefault("icons", {})
                for key, _ in LANGUAGES:
                    t["icons"][key] = f"icons/{key}-64.png"
                t["auditVersion"] = 6
            spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n")

            manifest_path = pkg / "manifest.json"
            manifest = json.loads(manifest_path.read_text())
            major, minor, patch = (manifest.get("version", "1.0.0").split(".") + ["0", "0"])[:3]
            manifest["version"] = f"{major}.{int(minor) + 1}.0"
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
            print(f"  {theme}: +{len(LANGUAGES)} icons, version -> {manifest['version']}, auditVersion 6")

            # 人工审核已通过 → 重新封存 reviewedHash（内容哈希由 app 计算，避免脚本复刻 JSON 规范化）
            spec = json.loads(spec_path.read_text())
            for t in spec:
                t["reviewed"] = True
            spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n")
            hash_bin = next((p for p in [
                os.path.expanduser("~/Applications/随手.app/Contents/MacOS/MarkNote"),
                str(ROOT / ".build/debug/MarkNote"),
            ] if os.path.exists(p)), None)
            if hash_bin:
                out = subprocess.run([hash_bin, "--hash-theme", str(pkg)],
                                     capture_output=True, text=True).stdout.strip()
                if len(out) == 64:
                    spec = json.loads(spec_path.read_text())
                    for t in spec:
                        t["reviewedHash"] = out
                    spec_path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n")
                    print(f"  {theme}: reviewedHash 已封存 {out[:12]}…")
                else:
                    print(f"  {theme}: 警告，未取得内容哈希（{out}）")
            else:
                print(f"  {theme}: 找不到 app 可执行文件，reviewedHash 未更新（用 --hash-theme 手动封存）")
        print("installed language icons into 4 theme packages")
        return

    made = build(REVIEW)
    sheet = preview_sheet(made, MARKET / "_review" / "lang-icons-preview.png")
    print("review icons ->", REVIEW)
    print("preview sheet ->", sheet)


if __name__ == "__main__":
    main()
