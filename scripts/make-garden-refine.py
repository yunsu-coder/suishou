#!/usr/bin/env python3
"""纸上花园（方向 B）配色细化评审稿：4 个微调方向 + 可读性硬指标。

用法: python3 scripts/make-garden-refine.py <outdir>
输出: garden-variants.png / garden-refined.png
"""

import importlib.util
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("gt", HERE / "make-game-themes.py")
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)

F, T, T_mix, mix_width = gt.F, gt.T, gt.T_mix, gt.mix_width
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO


def lum(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255 for i in (1, 3, 5))
    f = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = f(r), f(g), f(b)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def check(d, x, y, s, col, ok=True):
    if ok:
        d.line([(x, y + s * 0.5), (x + s * 0.36, y + s * 0.85), (x + s, y + s * 0.12)],
               fill=col, width=2, joint="curve")
    else:
        d.line([(x + s * 0.5, y), (x + s * 0.5, y + s * 0.6)], fill=col, width=2)
        d.ellipse([x + s * 0.42, y + s * 0.76, x + s * 0.58, y + s * 0.92], fill=col)


def base(paper, rail, sidebar, status, line, card, card2, sel, text, dim, accent, accent2, aux,
         icon_folder, icon_doc, icon_other):
    return dict(bg=paper, rail=rail, sidebar=sidebar, status=status, line=line, card=card,
                card2=card2, sel=sel, text=text, dim=dim, accent=accent, accent2=accent2,
                aux=aux, paper=card, ink=text,
                **{"icon.folder": icon_folder, "icon.doc": icon_doc, "icon.other": icon_other})


VARIANTS = [
    dict(id="B1", name="原稿 · 参考", mood="当前提案原样，绿偏灰、侧栏与编辑区几乎同色",
         colors=base("#F8F4EA", "#F0EADD", "#F3EEE2", "#EDE7DA", "#DED5C2", "#FFFFFF", "#F7F2E5",
                     "#E4EBD9", "#2F3A2E", "#7E8876", "#5F8468", "#D4899F", "#DFAE3A",
                     "#5F8468", "#5F8468", "#8A9486")),
    dict(id="B2", name="苔纸 · 更静一档", mood="纸更暖、绿更深，侧栏压暗一级，粉降饱和只留给开花",
         colors=base("#F7F2E6", "#EDE6D6", "#F0EADA", "#E8E1D0", "#D8CEB8", "#FFFCF4", "#F4EEDF",
                     "#E1E9D5", "#29342A", "#6E7A67", "#4C7757", "#C0808D", "#D2A63C",
                     "#38614A", "#4C7757", "#857F70")),
    dict(id="B3", name="雾青 · 冷调清爽", mood="纸偏冷白、主色转青瓷，辅助色用藕紫，最“清爽”",
         colors=base("#F5F7F3", "#E9EDE9", "#EEF1ED", "#E6EBE7", "#D3DAD4", "#FFFFFF", "#F1F4F0",
                     "#DCE8E1", "#25302B", "#6C7A73", "#3C7867", "#A98BB2", "#C9A227",
                     "#2C5F52", "#3C7867", "#8A948D")),
    dict(id="B4", name="木樨 · 暖调耐看", mood="纸最暖、主色转橄榄绿，强调色用赭橘，久看不刺眼",
         colors=base("#FAF5EC", "#F0E8DA", "#F4EDE0", "#EDE4D5", "#DFD3BE", "#FFFCF5", "#F7F0E2",
                     "#EFE7D3", "#33291F", "#7C6E5C", "#6B7F4F", "#C98A66", "#D9A93C",
                     "#55663D", "#6B7F4F", "#8C8175")),
]

SWATCHES = [("bg", "编辑纸"), ("sidebar", "侧栏"), ("accent", "主色"), ("accent2", "强调"), ("aux", "点缀")]


def swatch_row(d, x, y, colors, f):
    for k, (key, label) in enumerate(SWATCHES):
        cx = x + k * 58
        d.rounded_rectangle([cx, y, cx + 46, y + 40], radius=8, fill=colors[key], outline="#2A3648")
        T(d, cx, y + 46, label, f, "#8FA0BB")
        T(d, cx, y + 64, colors[key].upper(), F(MENLO, 10, 1), "#5F6E86")


def variants_page(out):
    W, H = 1840, 1290
    img, d = gt.page(W, H)
    T(d, 48, 34, "纸上花园 · 配色细化（方向 B）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "只调配色与层级，不动玩法：正文对比度、侧栏压暗分级、图标颜色层级、光标与选区配色。",
      F(HIRA, 15), "#93A3BE")

    for i, v in enumerate(VARIANTS):
        col, row = i % 2, i // 2
        x = 48 + col * 892
        y = 134 + row * 540
        c = v["colors"]
        d.rounded_rectangle([x, y, x + 860, y + 500], radius=16, fill="#111722", outline="#1F2937")
        T(d, x + 24, y + 20, f"{v['id']} · {v['name']}", F(HIRA, 19, 2), "#EFF4FF")
        T(d, x + 24, y + 52, v["mood"], F(HIRA, 12), "#8FA0BB")
        win = gt.render_garden(8, palette=v["colors"], refine=True)
        gt.paste_win(img, win, x + 24, y + 94, scale=0.36, radius=8, shadow=False)
        d.rounded_rectangle([x + 24, y + 94, x + 24 + 468, y + 94 + 288], radius=8,
                            outline="#2A3648", width=1)
        cx = x + 516
        swatch_row(d, cx, y + 96, c, F(HIRA, 11))
        stats = [("正文 / 编辑纸", c["text"], c["bg"], 4.5),
                 ("次级 / 编辑纸", c["dim"], c["bg"], 3.5),
                 ("主色 / 编辑纸", c["accent"], c["bg"], 4.0),
                 ("正文 / 选中行", c["text"], c["sel"], 4.5),
                 ("侧栏 / 编辑纸 分层", c["sidebar"], c["bg"], 1.0)]
        yy = y + 200
        for label, fg, bg, need in stats:
            ratio = contrast(fg, bg)
            ok = ratio >= need
            T(d, cx, yy, label, F(HIRA, 11), "#8FA0BB")
            T(d, cx + 250, yy, f"{ratio:.2f}:1", F(MENLO, 11, 1), "#B9C6DC", anchor="rt")
            d.rounded_rectangle([cx + 260, yy - 2, cx + 278, yy + 14], radius=4,
                                fill="#1F3A2C" if ok else "#3A1F22",
                                outline="#4E8F6E" if ok else "#8F4E52")
            check(d, cx + 264, yy + 1, 11, "#7FD1A8" if ok else "#E08C90", ok)
            yy += 26
        T_mix(d, cx, yy + 2, f"分层亮度差 {abs(lum(c['sidebar']) - lum(c['bg'])) * 100:.1f}%",
              F(MENLO, 10, 1), F(HIRA, 11), "#5F6E86")

    d.rounded_rectangle([48, H - 168, 1792, H - 48], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 150, "细化的四件事", F(HIRA, 16, 2), "#7FD1C0")
    T(d, 70, H - 118, "① 分层：编辑纸最亮 → 侧栏暗一档 → 图标栏再暗一档，避免整窗糊成一片。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 94, "② 图标分级：文件夹最深、Markdown 用主色、其他格式用中性灰绿，扫一眼就能分辨类型。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 70, "③ 强调色克制：粉色只出现在开花、里程碑这些奖励时刻；按钮与状态栏一律用主色。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, H - 46, "④ 光标与选区：光标 = 主色实线，选区 = 主色 26% 叠底，深浅两套纸色都测得清楚。",
      F(HIRA, 13), "#B9C6DC")
    img.save(out)
    return out


def detail_panel(img, d, x, y, w, h, title, colors):
    d.rounded_rectangle([x, y, x + w, y + h], radius=12, fill=colors["card"], outline=colors["line"])
    T(d, x + 18, y + 14, title, F(HIRA, 14, 2), colors["accent"])


def refined_page(out, variant):
    c = variant["colors"]
    W, H = 1840, 1420
    img, d = gt.page(W, H)
    T(d, 48, 34, f"纸上花园 · 细化稿（{variant['id']} {variant['name']}）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "左侧是完整窗口效果；右侧列出这轮改了哪些细节；下方是光标、选区、图标分级与 Markdown 可读性放大样。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 340, 46, W - 48, 90], radius=20, fill="#161C26", outline=c["accent"])
    T(d, W - 194, 68, "待人工审核 · 未安装", F(HIRA, 13), c["accent"], anchor="mm")

    win = gt.render_garden(8, palette=c, refine=True)
    gt.paste_win(img, win, 48, 150)

    x0 = 1400
    blocks = [
        ("分层与底纸", [f"编辑纸 {c['bg']}", f"侧栏 {c['sidebar']}（暗一档）",
                        f"图标栏 {c['rail']}（再暗一档）", f"卡片 {c['card']}"]),
        ("颜色分工", [f"主色 {c['accent']} 按钮 / 进度 / 光标",
                      f"强调 {c['accent2']} 只在开花与里程碑",
                      f"点缀 {c['aux']} 花蕊与克数刻度",
                      f"次级文字 {c['dim']}"]),
        ("图标颜色层级", [f"文件夹 {c['icon.folder']}", f"Markdown {c['icon.doc']}",
                          f"图片 / 音频 {c['icon.other']}"]),
        ("可读性（硬门槛）", [f"正文 {contrast(c['text'], c['bg']):.2f}:1 ≥ 4.5 通过",
                              f"次级 {contrast(c['dim'], c['bg']):.2f}:1 ≥ 3.5 通过",
                              f"主色 {contrast(c['accent'], c['bg']):.2f}:1 ≥ 4.0 通过"]),
    ]
    y0 = 150
    for title, lines in blocks:
        h = 56 + len(lines) * 26
        d.rounded_rectangle([x0, y0, W - 48, y0 + h], radius=12, fill="#141A24", outline="#243041")
        T(d, x0 + 18, y0 + 14, title, F(HIRA, 15, 2), c["accent"])
        for j, line in enumerate(lines):
            T(d, x0 + 18, y0 + 44 + j * 26, line, F(HIRA, 13), "#B9C6DC")
        y0 += h + 14

    # 细节放大样
    dy = 1000
    pw, ph = 424, 360
    detail_panel(img, d, 48, dy, pw, ph, "编辑光标 & 选区", c)
    T_mix(d, 70, dy + 60, "今天风很大，我把薄荷搬到了窗边。", F(MENLO, 14), F(HIRA, 15), c["text"])
    pre = "今天风很大，"
    x_s = 70 + mix_width(d, pre, F(MENLO, 14), F(HIRA, 15))
    x_e = 70 + mix_width(d, "今天风很大，我把薄荷搬到了窗边。", F(MENLO, 14), F(HIRA, 15))
    box = Image.new("RGB", (int(x_e - x_s), 24), c["accent"])
    img.paste(Image.blend(img.crop((int(x_s), dy + 58, int(x_e), dy + 82)), box, 0.26),
              (int(x_s), dy + 58))
    d.rectangle([x_e + 3, dy + 58, x_e + 5, dy + 82], fill=c["accent"])
    T(d, 70, dy + 100, "选区 = 主色 26% 叠底；光标 = 主色 2px 实线", F(HIRA, 12), c["dim"])
    T(d, 70, dy + 150, "选中行：", F(HIRA, 12), c["dim"])
    d.rounded_rectangle([150, dy + 142, 440, dy + 176], radius=8, fill=c["sel"])
    d.rounded_rectangle([150, dy + 142, 154, dy + 176], radius=2, fill=c["accent"])
    T(d, 168, dy + 150, "秋分 · 观察记.md", F(HIRA, 13), c["text"])
    T(d, 70, dy + 210, "正文示例：记录第七朵花开了。", F(HIRA, 14), c["text"])
    T(d, 70, dy + 244, "次级示例：写下 800 字它会开花。", F(HIRA, 14), c["dim"])
    T(d, 70, dy + 278, "强调示例：木槿（稀有）已入花园", F(HIRA, 14), c["accent2"])
    T(d, 70, dy + 312, "主色示例：今日生长 +1,240", F(HIRA, 14), c["accent"])

    dx2 = 48 + pw + 32
    detail_panel(img, d, dx2, dy, pw, ph, "语义图标颜色分级", c)
    glyphs = [("pot", c["icon.folder"], "文件夹 · 阳台花圃"),
              ("leaf", c["icon.doc"], "Markdown · 观察记.md"),
              ("bloom", c["icon.doc"], "文档 · 花期记录.md"),
              ("frame", c["icon.other"], "图片 · 第七朵花.png"),
              ("horn", c["icon.other"], "音频 · 风声.m4a")]
    for k, (key, col, label) in enumerate(glyphs):
        yy = dy + 54 + k * 44
        {"pot": gt.g_pot, "leaf": gt.g_leaf, "bloom": gt.g_bloom,
         "frame": gt.g_frame, "horn": gt.g_horn}[key](d, dx2 + 22, yy, 22, col, 2)
        T(d, dx2 + 60, yy + 2, label, F(HIRA, 13), c["text"])
        d.rounded_rectangle([dx2 + 320, yy + 2, dx2 + 348, yy + 20], radius=5, fill=col)

    dx3 = 48 + (pw + 32) * 2
    detail_panel(img, d, dx3, dy, pw, ph, "Markdown 渲染可读性", c)
    T(d, dx3 + 22, dy + 56, "秋分 · 阳台观察记", F(SONG, 20, 1), c["text"])
    d.line([(dx3 + 22, dy + 90), (dx3 + 400, dy + 90)], fill=c["line"])
    T(d, dx3 + 22, dy + 102, "今天风很大，我把薄荷搬到了窗边。", F(HIRA, 13), c["text"])
    d.ellipse([dx3 + 22, dy + 136, dx3 + 28, dy + 142], fill=c["accent"])
    T(d, dx3 + 40, dy + 130, "浇水 3 次 · 日照 4 小时", F(HIRA, 13), c["text"])
    d.rounded_rectangle([dx3 + 22, dy + 166, dx3 + 400, dy + 202], radius=8, fill=c["sel"],
                        outline=c["line"])
    T(d, dx3 + 38, dy + 176, "引用：第七朵花开了", F(HIRA, 13), c["accent"])
    T(d, dx3 + 22, dy + 218, "行内代码 ", F(HIRA, 13), c["text"])
    d.rounded_rectangle([dx3 + 92, dy + 214, dx3 + 178, dy + 240], radius=6, fill=c["card2"])
    T_mix(d, dx3 + 100, dy + 214, "字数 +800", F(MENLO, 11), F(HIRA, 12), c["text"])
    T(d, dx3 + 22, dy + 254, "链接 花期记录（主色，不抢正文）", F(HIRA, 13), c["accent"])
    T(d, dx3 + 22, dy + 292, "表格 / 引用 / 代码 / 链接四类都单独定色，避免整页同色。",
      F(HIRA, 12), c["dim"])

    dx4 = 48 + (pw + 32) * 3
    detail_panel(img, d, dx4, dy, pw, ph, "对照组：原稿 B1", c)
    T(d, dx4 + 22, dy + 56, "同一窗口，B1 原稿配色：", F(HIRA, 12), c["dim"])
    win1 = gt.render_garden(8, refine=False)
    gt.paste_win(img, win1, dx4 + 22, dy + 86, scale=0.29, radius=6, shadow=False)
    d.rounded_rectangle([dx4 + 22, dy + 86, dx4 + 399, dy + 318], radius=6, outline="#2A3648", width=1)
    T(d, dx4 + 22, dy + 326, "差异集中在：底纸冷暖、侧栏分层、粉色用量。", F(HIRA, 11), c["dim"])
    img.save(out)
    return out


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/game")
    outdir.mkdir(parents=True, exist_ok=True)
    pick = VARIANTS[1]
    if len(sys.argv) > 2:
        pick = next((v for v in VARIANTS if v["id"].lower() == sys.argv[2].lower()), pick)
    print(variants_page(outdir / "garden-variants.png"))
    print(refined_page(outdir / "garden-refined.png", pick))
    for v in VARIANTS[1:]:
        print(refined_page(outdir / f"garden-refined-{v['id'].lower()}.png", v))


if __name__ == "__main__":
    main()
