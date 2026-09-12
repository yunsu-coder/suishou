#!/usr/bin/env python3
"""深林夜主题包评审图：窗口预览 + 19 个图标（64/14px）+ 编辑器语法样张 + 门槛实测。

用法: python3 scripts/make-forest-night-review.py [输出.png]
"""

import importlib.util
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
syntax = _load("make-editor-syntax-review2")
fn_mod = _load("make-forest-night")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")

PKG = ROOT / "plugins-market/_review/theme-forest-night-v1"
P = fn_mod.P
M = fn_mod.METRICS


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/dark/forest-night-review.png"
    W, H = 1840, 1560
    img, d = gt.page(W, H)
    T(d, 48, 34, "深林夜 · 主题包评审稿（暗色单主题）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "左：窗口实拍比例渲染；右：门槛实测与专属资产；下：19 个语义图标（64px 与 14px）。色板与提案一致。",
      F(HIRA, 14), "#93A3BE")
    d.rounded_rectangle([W - 360, 46, W - 48, 90], radius=20, fill="#161C26", outline=P["accent"])
    T(d, W - 204, 68, "技术审计已通过 · 待你审核", F(HIRA, 13), P["accent_ink"], anchor="mm")

    win = review.render_window(P)
    gt.paste_win(img, win, 48, 130, scale=0.62, radius=10, shadow=True)
    d.rounded_rectangle([48, 130, 48 + int(1300 * 0.62), 130 + int(800 * 0.62)],
                        radius=10, outline="#2A3648", width=1)

    # 右栏：实测 + 资产
    sx = 900
    d.rounded_rectangle([sx, 130, W - 48, 626], radius=14, fill="#111722", outline="#1F2937")
    T(d, sx + 22, 146, "门槛实测（auditVersion 5 全项）", F(HIRA, 15, 2), "#7FD1A8")
    checks = [
        ("正文对比", f"{M['text']:.2f}:1", "≥4.5"),
        ("次级对比", f"{M['secondary']:.2f}:1", "≥3.5"),
        ("主色文字", f"{M['accent']:.2f}:1", "≥4.0"),
        ("代码高亮", f"{M['hl']:.2f}:1", "≥3.0"),
        ("提示色", f"{M['callout']:.2f}:1", "≥4.0"),
        ("语法内容色", f"{M['content_contrast']:.2f}:1", "≥4.5"),
        ("主色 ΔE", f"{M['core']:.0f}", "≥22"),
        ("内容 ΔE", f"{M['content']:.0f}", "≥12"),
        ("标记彩度", f"{M['marker_chroma']:.0f}", "≤30"),
        ("列表彩度", f"{M['visible_chroma']:.0f}", "≥12"),
        ("纸底亮度", f"{fn_mod.dark.lum(P['bg']):.3f}", "<0.2"),
        ("图标节点", "19 / 19", "全覆盖"),
    ]
    for i, (label, value, need) in enumerate(checks):
        col, row = i % 2, i // 2
        xx = sx + 22 + col * 240
        yy = 180 + row * 40
        T(d, xx, yy, label, F(HIRA, 12), "#8FA0BB")
        T_mix(d, xx, yy + 17, f"{value}　{need}", F(MONO, 11), F(HIRA, 11), "#7FD1A8")
    T(d, sx + 22, 424, "专属资产", F(HIRA, 15, 2), "#EFF4FF")
    T(d, sx + 22, 452, "字体：马善政楷书（标题，OFL 随包）· 苹方（正文）· JetBrains Mono（编辑，OFL 随包）",
      F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 476, "图标：19 槽位，按文件类型分色；透明字形、无底板、14px 可辨", F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 500, "动效：叶片光尘漂落 + 图标签弹跳 + 页签弹簧（尊重「减少动态效果」）", F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 524, "彩蛋：连点彩蛋图标 5 次 → 萤火 +「夜深了」", F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 548, "语法：33 个 --md-*（标记中性、内容分色、列表 / 序号 / 任务可见）", F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 572, "多彩钩子：标题三级 / 加粗 / 斜体各自色相（预览自动套用）", F(HIRA, 12), "#B9C6DC")
    T(d, sx + 22, 596, "亮暗：暗色单主题（dawn/night 都是这套），测试已放开为「真亮或真暗」", F(HIRA, 12), "#8FA0BB")

    # 图标表
    iy = 660
    d.rounded_rectangle([48, iy, W - 48, iy + 400], radius=16, fill="#111722", outline="#1F2937")
    T(d, 70, iy + 18, "19 个语义图标 · 64px 与 14px 实际尺寸（暗底）", F(HIRA, 16, 2), "#EFF4FF")
    mt = _load("make-misty-teal")
    for i, (key, fname, fn, _tier) in enumerate(mt.ICON_MAP):
        col, row = i % 7, i // 7
        cx = 70 + col * 246
        cy = iy + 56 + row * 116
        d.rounded_rectangle([cx - 12, cy - 10, cx + 214, cy + 92], radius=10, fill=P["surface"],
                            outline=P["line"])
        icon = Image.open(PKG / f"icons/{fname}-64.png").convert("RGBA")
        big = icon.resize((44, 44), Image.LANCZOS)
        img.paste(big, (cx, cy), big)
        small = icon.resize((14, 14), Image.LANCZOS)
        img.paste(small, (cx + 54, cy + 28), small)
        T(d, cx + 78, cy + 2, key.split(".")[-1], F(HIRA, 13), "#EFF4FF")
        T(d, cx + 78, cy + 24, fname, F(MONO, 10), "#8FA0BB")
        T(d, cx + 78, cy + 42, fn_mod.ICON_HUES[key].upper(), F(MONO, 10), "#6F7E96")
        d.rounded_rectangle([cx + 52, cy + 24, cx + 72, cy + 46], radius=4, outline="#2A3648")

    # 语法样张
    sy = 1080
    sample = dict(P["md"])
    sample["text"] = P["text"]
    sample["table_head"] = sample.get("table-head", sample["table"])
    sample["highlight_bg"] = "#3A2E12"
    sample["code_bg"] = P["code_bg"]
    d.rounded_rectangle([48, sy, 1200, sy + 430], radius=16, fill=P["bg"], outline=P["line"])
    T(d, 70, sy + 16, "编辑器语法样张（33 色 · 含列表 / 表格 / 终端 / 公式）", F(HIRA, 15, 2), P["md"]["h1"])
    for i, runs in enumerate(syntax.lines_for(sample, P["bg"], P["code_bg"], sample["highlight_bg"], "after")):
        syntax.draw_run(d, 70, sy + 50 + i * 30, runs)
    # 右侧色板
    d.rounded_rectangle([1230, sy, W - 48, sy + 430], radius=16, fill="#111722", outline="#1F2937")
    T(d, 1254, sy + 16, "配色", F(HIRA, 15, 2), "#EFF4FF")
    items = [("纸底", P["bg"]), ("面板", P["surface"]), ("代码底", P["code_bg"]),
             ("主色", P["accent"]), ("主色文字", P["accent_ink"]), ("正文", P["text"]),
             ("次级", P["--text-secondary"])]
    for i, (label, color) in enumerate(items):
        yy = sy + 50 + i * 40
        d.rounded_rectangle([1254, yy, 1318, yy + 28], radius=7, fill=color, outline="#2A3648")
        T(d, 1332, yy + 5, label, F(HIRA, 12), "#B9C6DC")
        T(d, 1332, yy + 22, color.upper(), F(MONO, 10), "#6F7E96")
    T(d, 1500, sy + 46, "多彩钩子 / 语法色", F(HIRA, 14, 2), "#EFF4FF")
    swatches = [("标题 1", P["md"]["h1"]), ("标题 2", P["md"]["h2"]), ("标题 3", P["md"]["h3"]),
                ("加粗", P["md"]["bold"]), ("斜体", P["md"]["italic"]), ("行内代码", P["md"]["code"]),
                ("链接", P["md"]["link"]), ("列表", P["md"]["list"]), ("序号", P["md"]["number"]),
                ("任务", P["md"]["task"]), ("提示", P["md"]["callout"]), ("高亮", P["md"]["highlight"])]
    for i, (label, color) in enumerate(swatches):
        col, row = i % 2, i // 2
        xx = 1500 + col * 160
        yy = sy + 76 + row * 52
        d.rounded_rectangle([xx, yy, xx + 44, yy + 30], radius=7, fill=color, outline="#2A3648")
        T(d, xx + 54, yy + 7, label, F(HIRA, 11), "#B9C6DC")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
