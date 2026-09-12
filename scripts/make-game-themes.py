#!/usr/bin/env python3
"""游戏化主题方向 · 高保真窗口评审稿（不安装、不进主题列表，仅供人工审核）。

用法: python3 scripts/make-game-themes.py <outdir>
输出: guild.png / garden.png / foundry.png / overview.png
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageFilter

SONG = "/System/Library/Fonts/Supplemental/Songti.ttc"  # 0 Black / 1 Bold / 3 Light
HIRA = "/System/Library/Fonts/Hiragino Sans GB.ttc"     # 0 W3 / 2 W6
MENLO = "/System/Library/Fonts/Menlo.ttc"               # 0 Regular / 1 Bold

WW, WH = 1300, 800
RADIUS = 14

_fc = {}


def F(path, size, index=0):
    key = (path, size, index)
    if key not in _fc:
        _fc[key] = ImageFont.truetype(path, size, index=index)
    return _fc[key]


def T(d, x, y, text, f, fill, anchor="lt"):
    d.text((x, y), text, font=f, fill=fill, anchor=anchor)


def _cjk(ch):
    return ord(ch) > 0x2E80


def _segments(text):
    segs, run, cur = [], "", None
    for ch in text:
        flag = _cjk(ch)
        if cur is None or flag == cur:
            run += ch
            cur = flag
        else:
            segs.append((run, cur))
            run, cur = ch, flag
    if run:
        segs.append((run, cur))
    return segs


def T_mix(d, x, y, text, f_latin, f_cjk, fill, align="left"):
    """等宽字体渲染 ASCII、CJK 回落到中文字体（与真实编辑器一致）。"""
    base = y + max(f_latin.getmetrics()[0], f_cjk.getmetrics()[0])
    segs = _segments(text)
    total = sum(d.textlength(s, font=(f_cjk if c else f_latin)) for s, c in segs)
    cx = x - total if align == "right" else (x - total / 2 if align == "center" else x)
    for s, c in segs:
        fnt = f_cjk if c else f_latin
        d.text((cx, base), s, font=fnt, fill=fill, anchor="ls")
        cx += d.textlength(s, font=fnt)
    return cx


def mix_width(d, text, f_latin, f_cjk):
    return sum(d.textlength(s, font=(f_cjk if c else f_latin)) for s, c in _segments(text))


def g_sword(d, x, y, s, c):
    d.line([(x + s * 0.14, y + s * 0.86), (x + s * 0.86, y + s * 0.14)], fill=c, width=2)
    d.line([(x + s * 0.14, y + s * 0.14), (x + s * 0.86, y + s * 0.86)], fill=c, width=2)
    d.line([(x + s * 0.10, y + s * 0.60), (x + s * 0.40, y + s * 0.90)], fill=c, width=2)
    d.line([(x + s * 0.60, y + s * 0.10), (x + s * 0.90, y + s * 0.40)], fill=c, width=2)


PALETTES = {
    "guild": dict(
        bg="#1B1410", rail="#160F0A", sidebar="#221A13", status="#241C15",
        line="#3A2C20", card="#2B2118", card2="#332719", sel="#3B2A18",
        text="#F1E5CE", dim="#B39C7F", accent="#D9A441", accent2="#C4552F",
        aux="#7FA05A", paper="#EFE0BE", ink="#241B12",
    ),
    "garden": dict(
        bg="#F8F4EA", rail="#F0EADD", sidebar="#F3EEE2", status="#EDE7DA",
        line="#DED5C2", card="#FFFFFF", card2="#F7F2E5", sel="#E4EBD9",
        text="#2F3A2E", dim="#7E8876", accent="#5F8468", accent2="#D4899F",
        aux="#DFAE3A", paper="#FFFFFF", ink="#2F3A2E",
    ),
    "foundry": dict(
        bg="#15171B", rail="#101216", sidebar="#1A1D22", status="#1D2026",
        line="#2B303A", card="#22262D", card2="#282D35", sel="#33302A",
        text="#EDE9E0", dim="#9AA0AB", accent="#C08A4A", accent2="#5B8DB8",
        aux="#8FA98C", paper="#EFEDE7", ink="#191C21",
    ),
}


def fonts(kind):
    if kind == "guild":
        return dict(title=F(SONG, 31, 0), head=F(SONG, 19, 1), body=F(SONG, 15, 3),
                    code=F(MENLO, 13), ui=F(HIRA, 13), uib=F(HIRA, 13, 2),
                    small=F(SONG, 12, 3), num=F(MENLO, 12, 1))
    if kind == "garden":
        return dict(title=F(SONG, 31, 3), head=F(SONG, 19, 1), body=F(HIRA, 14),
                    code=F(MENLO, 13), ui=F(HIRA, 13), uib=F(HIRA, 13, 2),
                    small=F(HIRA, 12), num=F(MENLO, 12))
    return dict(title=F(SONG, 31, 0), head=F(SONG, 19, 1), body=F(SONG, 14, 3),
                code=F(MENLO, 13), ui=F(HIRA, 13), uib=F(HIRA, 13, 2),
                small=F(HIRA, 12), num=F(MENLO, 12, 1))


# ---------------------------------------------------------------- 画布 / 拼贴

def page(w, h, bg="#0B0D12"):
    img = Image.new("RGB", (w, h), bg)
    return img, ImageDraw.Draw(img)


def paste_win(target, win, x, y, scale=1.0, radius=RADIUS, shadow=True):
    if scale != 1.0:
        win = win.resize((int(win.width * scale), int(win.height * scale)), Image.LANCZOS)
    w, h = win.size
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w - 1, h - 1], radius=radius, fill=255)
    if shadow:
        pad = 90
        sh = Image.new("L", (w + pad * 2, h + pad * 2), 0)
        ImageDraw.Draw(sh).rounded_rectangle(
            [pad, pad + 6, pad + w, pad + h + 6], radius=radius, fill=120)
        sh = sh.filter(ImageFilter.GaussianBlur(20))
        target.paste((0, 0, 0), (x - pad, y - pad), sh)
    target.paste(win, (x, y), mask)


# ---------------------------------------------------------------- 语义图标

def g_box(d, x, y, s, c, lw=2, opened=False):
    """书匣 / 收纳箱 = 文件夹"""
    d.rounded_rectangle([x, y + s * 0.22, x + s, y + s], radius=s * 0.16, outline=c, width=lw)
    d.line([(x, y + s * 0.44), (x + s, y + s * 0.44)], fill=c, width=lw)
    if opened:
        d.line([(x + s * 0.30, y + s * 0.22), (x + s * 0.44, y + s * 0.06),
                (x + s * 0.94, y + s * 0.06)], fill=c, width=lw, joint="curve")
    else:
        d.rectangle([x + s * 0.40, y + s * 0.30, x + s * 0.60, y + s * 0.40], outline=c, width=max(1, lw - 1))


def g_scroll(d, x, y, s, c, lw=2):
    """卷轴 = Markdown"""
    d.rounded_rectangle([x + s * 0.18, y + s * 0.08, x + s * 0.82, y + s * 0.92],
                        radius=s * 0.10, outline=c, width=lw)
    for i in range(3):
        yy = y + s * (0.32 + i * 0.20)
        d.line([(x + s * 0.32, yy), (x + s * 0.68 - i * s * 0.10, yy)], fill=c, width=max(1, lw - 1))


def g_rune(d, x, y, s, c, lw=2):
    """符文石 = 代码"""
    d.polygon([(x + s * 0.50, y), (x + s * 0.96, y + s * 0.26), (x + s * 0.96, y + s * 0.76),
               (x + s * 0.50, y + s), (x + s * 0.04, y + s * 0.76), (x + s * 0.04, y + s * 0.26)],
              outline=c, width=lw)
    d.line([(x + s * 0.36, y + s * 0.52), (x + s * 0.30, y + s * 0.40)], fill=c, width=lw)
    d.line([(x + s * 0.64, y + s * 0.52), (x + s * 0.70, y + s * 0.40)], fill=c, width=lw)
    d.line([(x + s * 0.34, y + s * 0.62), (x + s * 0.66, y + s * 0.62)], fill=c, width=lw)


def g_frame(d, x, y, s, c, lw=2):
    """画框 = 图片"""
    d.rounded_rectangle([x + s * 0.08, y + s * 0.14, x + s * 0.92, y + s * 0.86],
                        radius=s * 0.10, outline=c, width=lw)
    d.polygon([(x + s * 0.20, y + s * 0.70), (x + s * 0.42, y + s * 0.42),
               (x + s * 0.62, y + s * 0.70)], outline=c, width=max(1, lw - 1))
    d.ellipse([x + s * 0.60, y + s * 0.26, x + s * 0.74, y + s * 0.40], fill=c)


def g_horn(d, x, y, s, c, lw=2):
    """号角 = 音频"""
    d.polygon([(x + s * 0.12, y + s * 0.34), (x + s * 0.50, y + s * 0.34),
               (x + s * 0.86, y + s * 0.10), (x + s * 0.86, y + s * 0.90),
               (x + s * 0.50, y + s * 0.66), (x + s * 0.12, y + s * 0.66)],
              outline=c, width=lw)


def g_leaf(d, x, y, s, c, lw=2):
    """叶片 = Markdown"""
    d.line([(x + s * 0.5, y + s), (x + s * 0.5, y + s * 0.38)], fill=c, width=lw)
    d.arc([x + s * 0.12, y + s * 0.02, x + s * 0.86, y + s * 0.66], start=200, end=340, fill=c, width=lw)
    d.arc([x + s * 0.14, y + s * 0.34, x + s * 0.86, y + s * 0.98], start=20, end=160, fill=c, width=lw)


def g_pot(d, x, y, s, c, lw=2):
    """花盆 = 文件夹"""
    d.polygon([(x + s * 0.16, y + s * 0.56), (x + s * 0.84, y + s * 0.56),
               (x + s * 0.72, y + s), (x + s * 0.28, y + s)], outline=c, width=lw)
    d.line([(x + s * 0.5, y + s * 0.56), (x + s * 0.5, y + s * 0.20)], fill=c, width=lw)
    d.ellipse([x + s * 0.22, y + s * 0.12, x + s * 0.46, y + s * 0.32], outline=c, width=max(1, lw - 1))
    d.ellipse([x + s * 0.54, y + s * 0.18, x + s * 0.78, y + s * 0.38], outline=c, width=max(1, lw - 1))


def g_bloom(d, x, y, s, c, lw=2):
    """花 = 文档 / 里程碑"""
    for i in range(5):
        import math
        a = math.radians(90 + i * 72)
        cx, cy = x + s * 0.5 + math.cos(a) * s * 0.26, y + s * 0.42 + math.sin(a) * s * 0.26
        d.ellipse([cx - s * 0.16, cy - s * 0.16, cx + s * 0.16, cy + s * 0.16], outline=c, width=lw)
    d.ellipse([x + s * 0.42, y + s * 0.34, x + s * 0.58, y + s * 0.50], fill=c)
    d.line([(x + s * 0.5, y + s * 0.66), (x + s * 0.5, y + s)], fill=c, width=lw)


def g_type(d, x, y, s, c, lw=2):
    """铅字块 = 文档 / 代码"""
    d.rounded_rectangle([x + s * 0.10, y + s * 0.16, x + s * 0.90, y + s * 0.84],
                        radius=s * 0.10, outline=c, width=lw)
    d.line([(x + s * 0.26, y + s * 0.40), (x + s * 0.74, y + s * 0.40)], fill=c, width=lw)
    d.line([(x + s * 0.50, y + s * 0.40), (x + s * 0.50, y + s * 0.70)], fill=c, width=lw)
    d.line([(x + s * 0.34, y + s * 0.70), (x + s * 0.66, y + s * 0.70)], fill=c, width=lw)
    d.line([(x + s * 0.10, y + s * 0.84), (x + s * 0.30, y + s * 0.94)], fill=c, width=max(1, lw - 1))
    d.line([(x + s * 0.70, y + s * 0.94), (x + s * 0.90, y + s * 0.84)], fill=c, width=max(1, lw - 1))


def g_tray(d, x, y, s, c, lw=2):
    """字盘 = 文件夹"""
    d.rounded_rectangle([x + s * 0.06, y + s * 0.18, x + s * 0.94, y + s * 0.92],
                        radius=s * 0.10, outline=c, width=lw)
    d.line([(x + s * 0.06, y + s * 0.42), (x + s * 0.94, y + s * 0.42)], fill=c, width=max(1, lw - 1))
    d.line([(x + s * 0.50, y + s * 0.18), (x + s * 0.50, y + s * 0.92)], fill=c, width=max(1, lw - 1))
    d.line([(x + s * 0.06, y + s * 0.67), (x + s * 0.94, y + s * 0.67)], fill=c, width=max(1, lw - 1))


def g_search(d, x, y, s, c, lw=2):
    d.ellipse([x + s * 0.08, y + s * 0.08, x + s * 0.68, y + s * 0.68], outline=c, width=lw)
    d.line([(x + s * 0.66, y + s * 0.66), (x + s * 0.94, y + s * 0.94)], fill=c, width=lw)


def g_paw(d, x, y, s, c):
    d.ellipse([x + s * 0.34, y + s * 0.42, x + s * 0.66, y + s * 0.78], fill=c)
    for i, (dx, dy) in enumerate(((0.16, 0.16), (0.40, 0.06), (0.64, 0.16))):
        d.ellipse([x + s * dx, y + s * dy, x + s * (dx + 0.20), y + s * (dy + 0.22)], fill=c)


# ---------------------------------------------------------------- 通用窗口骨架

def chrome(kind, p):
    img = Image.new("RGB", (WW, WH), p["bg"])
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 55, WH], fill=p["rail"])
    d.rectangle([56, 0, 329, WH], fill=p["sidebar"])
    d.line([(55, 0), (55, WH)], fill=p["line"])
    d.line([(329, 0), (329, WH)], fill=p["line"])
    d.rectangle([330, 766, WW, WH], fill=p["status"])
    d.line([(330, 766), (WW, 766)], fill=p["line"])
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        d.ellipse([20 + i * 22, 16, 33 + i * 22, 29], fill=c)
    return img, d


def header(d, p, f, title="资源管理器", sub=None):
    T(d, 76, 48, title, f["ui"], p["text"])
    for i in range(3):
        d.ellipse([288 + i * 9, 54, 293 + i * 9, 59], fill=p["dim"])
    d.rounded_rectangle([74, 82, 312, 114], radius=9, fill=p["card"], outline=p["line"])
    g_search(d, 84, 91, 14, p["dim"], 2)
    T(d, 106, 90, "搜索文件", f["ui"], p["dim"])


def tree(d, p, f, rows, y0=132, selected=0, icon_colors=None):
    """rows: (indent, icon_key, label, trailing)"""
    for i, (indent, key, label, trail) in enumerate(rows):
        y = y0 + i * 32
        if i == selected:
            d.rounded_rectangle([66, y - 4, 320, y + 26], radius=7, fill=p["sel"])
        x = 74 + indent * 18
        if indent:
            T(d, x - 14, y + 2, "›", f["ui"], p["dim"])
        else:
            T(d, x - 14, y, "⌄", f["ui"], p["dim"])
        icon_x = x + 6
        s = 17
        {
            "box": g_box, "scroll": g_scroll, "rune": g_rune, "frame": g_frame,
            "horn": g_horn, "leaf": g_leaf, "pot": g_pot, "bloom": g_bloom,
            "type": g_type, "tray": g_tray,
        }[key](d, icon_x, y + 1, s,
               (icon_colors[i] if icon_colors and i < len(icon_colors) else p["accent"]), 2)
        T(d, icon_x + 26, y + 2, label, f["ui"], p["text"] if i == selected else p["text"])
        if trail:
            T(d, 312, y + 2, trail, f["num"] if hasattr(f["num"], "getbbox") else f["ui"],
              p["accent2"] if kind_color(trail) else p["dim"], anchor="rt")


def kind_color(trail):
    return False


def tabbar(d, p, f, icon, name, x=346):
    d.rounded_rectangle([x, 10, x + 232, 40], radius=8, fill=p["card"])
    d.rounded_rectangle([x, 10, x + 232, 40], radius=8, outline=p["line"])
    if icon == "scroll":
        g_scroll(d, x + 14, 18, 14, p["accent"], 2)
    elif icon == "leaf":
        g_leaf(d, x + 14, 18, 14, p["accent"], 3)
    else:
        g_type(d, x + 14, 18, 14, p["accent"], 2)
    T(d, x + 38, 17, name, f["ui"], p["text"])
    T(d, x + 214, 16, "×", f["ui"], p["dim"])


def split_panes(d, p, x1=820):
    d.line([(x1, 52), (x1, 758)], fill=p["line"])
    d.rounded_rectangle([x1 - 3, 330, x1 + 3, 470], radius=3, fill=p["line"])


def statusbar_static(d, p, f, right):
    T(d, WW - 24, 780, right, f["ui"], p["dim"], anchor="rt")


def rail_icons(d, p, kind):
    for i, key in enumerate(("box", "tray") if kind == "foundry" else ("box", "frame")):
        y = 132 + i * 46
        d.rounded_rectangle([14, y, 42, y + 28], radius=8, fill=p["card"] if i == 0 else None,
                            outline=None if i == 0 else p["line"])
        {"box": g_box, "tray": g_tray, "frame": g_frame}[key](d, 21, y + 7, 14, p["accent"] if i == 0 else p["dim"], 2)


def win_bottom(d, p, f, left):
    T(d, 74, 776, left, f["num"], p["dim"])


# ---------------------------------------------------------------- 方向 A · 冒险者公会

def render_guild(stage=8, anim=None):
    a = dict(xp_frac=None, toast=1.0, flag_gold=False, reveal=-1, glow=1.0,
             flash=0.0, count="1,842 字")
    if anim:
        a.update(anim)
    p = dict(PALETTES["guild"])
    f = fonts("guild")
    lv = {1: 1, 8: 12, 20: 27}[stage]
    if a.get("level_bump"):
        lv += 1
    xp_done, xp_all = {1: 60, 8: 1240, 20: 9980}[stage], {1: 300, 8: 2000, 20: 12000}[stage]
    if a["xp_frac"] is not None:
        xp_done = int(xp_all * a["xp_frac"])
    if stage == 1:
        p["accent"] = "#8A7550"
        p["accent2"] = "#7A5A44"
    img, d = chrome("guild", p)

    # 大厅氛围：火把光 / 旗帜 / 雕像
    glow = Image.new("RGB", (WW, WH), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    if stage >= 8 and a["glow"] > 0:
        gd.ellipse([WW - 360, -240, WW + 200, 300], fill=(72, 44, 14))
        gd.ellipse([-160, WH - 420, 300, WH + 120], fill=(38, 26, 12))
        glow = glow.filter(ImageFilter.GaussianBlur(90))
        img = Image.blend(img, Image.blend(img, glow, 0.0), 0.0)
        img = Image.blend(img, Image.composite(glow, img, Image.new("L", (WW, WH), 46)), 0.28 * a["glow"])
        d = ImageDraw.Draw(img)

    if stage >= 8:
        # 公会旗帜
        bx, by = WW - 108, 18
        d.line([(bx, by), (bx, by + 78)], fill=p["accent"], width=3)
        d.polygon([(bx, by), (bx + 70, by + 12), (bx, by + 30)],
                  fill="#F2C14E" if a["flag_gold"] else p["accent2"])
        T(d, bx + 12, by + 6, f"Lv.{lv}", f["num"], p["paper"])
    if stage >= 20:
        # 传说雕像
        sx, sy = WW - 330, 690
        d.rectangle([sx - 26, sy + 44, sx + 26, sy + 58], fill=p["accent"])
        d.polygon([(sx - 20, sy + 44), (sx + 20, sy + 44), (sx + 14, sy + 10), (sx - 14, sy + 10)],
                  fill=p["accent2"])
        d.ellipse([sx - 12, sy - 12, sx + 12, sy + 12], fill=p["accent"])
        T(d, sx, sy + 68, "执笔者纪念像", f["small"], p["dim"], anchor="mt")

    rail_icons(d, p, "guild")
    header(d, p, f)

    rows = [
        (0, "box", "冒险档案", ""),
        (1, "box", "第一章 · 远征", ""),
        (2, "scroll", "讨伐书.md", ""),
        (2, "scroll", "营地物资.md", ""),
        (2, "rune", "世界设定.md", ""),
        (2, "frame", "北境地图.png", ""),
        (1, "box", "支线 · 商会", ""),
    ][: 5 if stage == 1 else 7]
    tree(d, p, f, rows, selected=2)

    # 委托卡
    cy = 596
    d.rounded_rectangle([72, cy, 314, cy + 150], radius=12, fill=p["card"], outline=p["line"])
    T(d, 88, cy + 14, "今日委托" if stage > 1 else "布告板", f["uib"], p["accent"])
    if stage == 1:
        T(d, 88, cy + 44, "写满 800 字解锁委托", f["small"], p["dim"])
        d.rounded_rectangle([88, cy + 76, 298, cy + 92], radius=8, fill=p["card2"])
        T(d, 88, cy + 110, "奖励：？？？", f["small"], p["dim"])
    else:
        T(d, 88, cy + 42, "写满 800 字", f["body"], p["text"])
        d.rounded_rectangle([88, cy + 74, 298, cy + 90], radius=8, fill=p["card2"])
        d.rounded_rectangle([88, cy + 74, 88 + int(210 * 0.78), cy + 90], radius=8, fill=p["accent"])
        T_mix(d, 88, cy + 94, "620 / 800 字", f["num"], f["ui"], p["dim"])
        T(d, 298, cy + 100, "+120 XP", f["num"], p["accent"], anchor="rt")
        d.line([(88, cy + 124), (298, cy + 124)], fill=p["line"])
        T(d, 88, cy + 130, "公会声望 +2 · 连续 12 天", f["small"], p["dim"])

    tabbar(d, p, f, "scroll", "讨伐书 · 第三章")
    split_panes(d, p)

    # 源码
    src = [
        ("# 讨伐书 · 第三章", "head"),
        ("## 目标", "head"),
        ("- [x] 侦察黑松林", "body"),
        ("- [ ] 撰写营地物资清单", "body"),
        ("> 奖励 120 XP · 声望 +2", "dim"),
    ]
    y = 78
    for text, sty in src:
        shown = text
        if a["reveal"] >= 0 and text.startswith("- [ ] 撰写"):
            shown = text[: max(0, a["reveal"])]
        if sty in ("body", "dim"):
            end = T_mix(d, 360, y, shown, f["code"], f["body"], p["text"])
            if a["reveal"] >= 0 and text.startswith("- [ ] 撰写"):
                d.rectangle([end + 2, y + 2, end + 8, y + 20], fill=p["accent"])
        else:
            T(d, 360, y, text, f["body"], p["text"])
        y += 34 if sty != "dim" else 30

    # 预览
    T(d, 852, 74, "讨伐书 · 第三章", f["title"], p["text"])
    d.line([(852, 122), (1264, 122)], fill=p["line"])
    T(d, 852, 142, "目标", f["head"], p["text"])
    for i, (txt, done) in enumerate((("侦察黑松林", True), ("撰写营地物资清单", False))):
        yy = 182 + i * 32
        d.rounded_rectangle([852, yy + 2, 868, yy + 18], radius=4, outline=p["accent"], width=2)
        if done:
            d.line([(855, yy + 10), (859, yy + 15), (866, yy + 4)], fill=p["accent"], width=2)
        T(d, 880, yy, txt, f["body"], p["text"])
    d.rounded_rectangle([852, 262, 1264, 306], radius=8, fill=p["card"], outline=p["line"])
    T(d, 868, 276, "奖励 120 XP · 声望 +2", f["body"], p["accent"])

    # 进度环
    d.ellipse([1000, 400, 1130, 530], outline=p["line"], width=12)
    d.arc([1000, 400, 1130, 530], start=-90, end=-90 + 360 * (xp_done / xp_all), fill=p["accent"], width=12)
    T(d, 1065, 448, f"Lv.{lv}", f["head"], p["accent"], anchor="mm")
    T(d, 1065, 476, "长夜执笔者", f["small"], p["dim"], anchor="mm")
    T(d, 1065, 560, "写满本章即可升级", f["small"], p["dim"], anchor="mm")

    # 状态栏：经验条
    d.rounded_rectangle([344, 778, 420, 800], radius=11, fill=p["accent"])
    T(d, 382, 789, f"Lv.{lv}", f["num"], p["ink"], anchor="mm")
    d.rounded_rectangle([432, 783, 700, 795], radius=6, fill=p["card2"])
    d.rounded_rectangle([432, 783, 432 + int(268 * xp_done / xp_all), 795], radius=6, fill=p["accent"])
    T(d, 712, 780, f"{xp_done:,} / {xp_all:,} XP", f["num"], p["dim"])
    g_sword(d, 902, 780, 16, p["accent2"])
    T(d, 926, 780, "连续写作 12 天", f["ui"], p["accent2"])
    statusbar_static(d, p, f, f"已保存 · {a['count']}")

    # 成就横幅
    if stage > 1 and a["toast"] > 0:
        oy = int((1 - a["toast"]) * 46)
        d.rounded_rectangle([826, 654 + oy, 1272, 730 + oy], radius=12, fill=p["card"],
                            outline=p["accent"], width=2)
        d.polygon([(846, 692 + oy), (866, 664 + oy), (886, 692 + oy), (866, 720 + oy)], fill=p["accent"])
        T(d, 902, 672 + oy, "成就达成 · 破晓执笔", f["uib"], p["text"])
        T(d, 902, 698 + oy, "连续 7 天在日出前写作", f["small"], p["dim"])
        T(d, 1252, 700 + oy, "+250 XP", f["num"], p["accent"], anchor="rt")
    if a["flash"] > 0:
        ov = Image.new("RGB", (WW, WH), (255, 214, 140))
        img = Image.blend(img, ov, 0.30 * a["flash"])
    return img


# ---------------------------------------------------------------- 方向 B · 纸上花园

def render_garden(stage=8, anim=None, palette=None, refine=False):
    a = dict(growth=1.0, bloom=1.6, butterfly=None, toast=1.0, count="612 字")
    if anim:
        a.update(anim)
    if a["butterfly"] is None:
        a["butterfly"] = 0.35 if stage > 1 else 0.0
    p = dict(PALETTES["garden"])
    if palette:
        p.update(palette)
    f = fonts("garden")
    if stage == 1 and not palette:
        p["accent"] = "#8B9C86"
        p["accent2"] = "#C0A9A2"
    img, d = chrome("garden", p)

    rail_icons(d, p, "garden")
    header(d, p, f)

    rows = [
        (0, "pot", "阳台花圃", ""),
        (1, "leaf", "秋分 · 观察记.md", ""),
        (1, "leaf", "薄荷养护.md", ""),
        (1, "bloom", "花期记录.md", ""),
        (1, "frame", "第七朵花.png", ""),
        (1, "leaf", "旅行清单.md", ""),
    ][: 3 if stage == 1 else 6]
    tiers = None
    if refine:
        # 图标颜色分级：文件夹最深、文档用主色、其他格式用中性灰绿
        tiers = [p["icon.folder"], p["icon.doc"], p["icon.doc"], p["icon.doc"],
                 p["icon.other"], p["icon.doc"]][: len(rows)]
    tree(d, p, f, rows, selected=1, icon_colors=tiers)
    if refine:
        y = 132 + 32
        d.rounded_rectangle([66, y - 4, 69, y + 26], radius=2, fill=p["accent"])
    # 每篇文档右侧的生长刻度
    for i in range(len(rows)):
        if i == 0:
            continue
        y = 132 + i * 32
        d.rounded_rectangle([268, y + 8, 312, y + 14], radius=3, fill=p["card2"])
        d.rounded_rectangle([268, y + 8, 268 + int(44 * (0.35 + 0.65 * ((i * 37) % 10) / 10)), y + 14],
                            radius=3, fill=p["accent"])

    # 花园面板
    cy = 604
    d.rounded_rectangle([72, cy, 314, cy + 142], radius=12, fill=p["card"], outline=p["line"])
    T(d, 88, cy + 14, "我的花园 · 秋", f["uib"], p["accent"])
    T_mix(d, 298, cy + 10, "盛开 7 · 稀有 2", f["num"], f["ui"], p["dim"], align="right")
    for i in range(9):
        gx, gy = 94 + i * 24, cy + 50
        if i < 7:
            g_bloom(d, gx, gy, 20, p["accent2"] if i in (2, 5) else p["accent"], 2)
        else:
            d.ellipse([gx + 4, gy + 4, gx + 16, gy + 16], outline=p["line"], width=2)
    d.line([(88, cy + 92), (298, cy + 92)], fill=p["line"])
    T(d, 88, cy + 100, "今日生长 +1,240", f["body"], p["text"])
    d.rounded_rectangle([88, cy + 124, 298, cy + 134], radius=5, fill=p["card2"])
    d.rounded_rectangle([88, cy + 124, 88 + 150, cy + 134], radius=5, fill=p["accent"])

    tabbar(d, p, f, "leaf", "秋分 · 观察记")
    split_panes(d, p)

    src = [
        "# 秋分 · 阳台观察记", "今天风很大，我把薄荷搬到了窗边。",
        "- 浇水 3 次 · 日照 4 小时", "> 第七朵花开了", "[[花期记录]]",
    ]
    y = 78
    for i, text in enumerate(src):
        T_mix(d, 360, y, text, f["code"], f["body"], p["text"] if i < 3 else p["dim"])
        if refine and i == 1:
            pre = "今天风很大，"
            x0 = 360 + mix_width(d, pre, f["code"], f["body"])
            x1 = 360 + mix_width(d, text, f["code"], f["body"])
            band = Image.new("RGB", (max(1, int(x1 - x0)), 22), p["accent"])
            img.paste(Image.blend(img.crop((int(x0), y, int(x1), y + 22)), band, 0.26), (int(x0), y))
            d.rectangle([x1 + 3, y, x1 + 5, y + 20], fill=p["accent"])
        y += 32
    d.rounded_rectangle([360, y + 10, 780, y + 88], radius=10, fill=p["card"], outline=p["line"])
    T(d, 376, y + 24, "在花园里，这篇文档长了一株薄荷。", f["body"], p["text"])
    T(d, 376, y + 54, "写下 800 字它会开花；闲置 7 天会休眠。", f["small"], p["dim"])

    T(d, 852, 74, "秋分 · 阳台观察记", f["title"], p["text"])
    d.line([(852, 122), (1264, 122)], fill=p["line"])
    T(d, 852, 142, "今天风很大，我把薄荷搬到了窗边。", f["body"], p["text"])
    for i, text in enumerate(["- 浇水 3 次 · 日照 4 小时", "- 记录：第七朵花开了"]):
        yy = 190 + i * 30
        d.ellipse([852, yy + 6, 858, yy + 12], fill=p["accent"])
        T(d, 872, yy, text, f["body"], p["text"])
    d.rounded_rectangle([852, 268, 1264, 312], radius=8, fill=p["sel"])
    T(d, 868, 282, "第七朵花开了", f["body"], p["accent"])

    # 花园插画
    gy = 560
    d.rounded_rectangle([852, 380, 1264, 600], radius=14, fill=p["card"], outline=p["line"])
    T(d, 872, 396, "本季花园", f["uib"], p["accent"])
    for i, h in enumerate((54, 78, 40, 92, 66)):
        bx = 900 + i * 66
        hh = h * a["growth"]
        d.line([(bx, gy), (bx, gy - hh)], fill=p["accent"], width=3)
        for side in (-1, 1):
            ly = gy - hh * (0.40 if side < 0 else 0.64)
            d.arc([bx + side * 3 - 17, ly - 11, bx + side * 3 + 13, ly + 11],
                  start=200 if side < 0 else 20, end=340 if side < 0 else 160,
                  fill=p["accent"], width=3)
        if hh > 20:
            col = p["accent2"] if i % 2 else p["accent"]
            open_rate = min(1.0, max(0.0, (a["bloom"] - i * 0.12) * 1.6))
            for k in range(6):
                import math
                ang = math.radians(k * 60)
                r = 13 * open_rate
                d.ellipse([bx + math.cos(ang) * r - 7 * open_rate, gy - hh - 14 + math.sin(ang) * r - 7 * open_rate,
                           bx + math.cos(ang) * r + 7 * open_rate, gy - hh - 14 + math.sin(ang) * r + 7 * open_rate],
                          outline=col, width=2)
            d.ellipse([bx - 4, gy - hh - 18, bx + 4, gy - hh - 10], fill=p["aux"])
    d.rectangle([880, gy, 1236, gy + 6], fill=p["line"])

    # 蝴蝶彩蛋
    if a["butterfly"] > 0:
        import math
        bxc = 1186 + math.sin(a["butterfly"] * 6.28) * 34
        byc = 344 + math.sin(a["butterfly"] * 12.56) * 12
        for sx in (-1, 1):
            for k, (rx, ry) in enumerate(((15, 12), (10, 8))):
                cy2 = byc + sx * 2 + k * 14
                x0 = bxc + (5 if sx > 0 else -5 - rx * 2)
                x1 = bxc + (5 + rx * 2 if sx > 0 else -5)
                d.ellipse([x0, cy2 - ry, x1, cy2 + ry], outline=p["accent2"], width=2)
        d.line([(bxc, byc - 12), (bxc, byc + 22)], fill=p["text"], width=2)
        d.line([(bxc, byc - 12), (bxc - 8, byc - 22)], fill=p["text"], width=2)
        d.line([(bxc, byc - 12), (bxc + 8, byc - 22)], fill=p["text"], width=2)

    # 状态栏
    d.rounded_rectangle([344, 778, 458, 800], radius=11, fill=p["accent"])
    T_mix(d, 401, 781, "今日 +1,240", f["num"], f["ui"], p["paper"], align="center")
    d.rounded_rectangle([472, 783, 672, 795], radius=6, fill=p["card2"])
    d.rounded_rectangle([472, 783, 472 + 128, 795], radius=6, fill=p["accent"])
    T_mix(d, 688, 774, "生长 128 / 200", f["num"], f["ui"], p["dim"])
    T(d, 900, 780, "花期：秋分 · 木槿", f["ui"], p["accent2"])
    statusbar_static(d, p, f, f"已保存 · {a['count']}")

    if stage > 1 and a["toast"] > 0:
        oy = int((1 - a["toast"]) * 46)
        d.rounded_rectangle([826, 654 + oy, 1272, 730 + oy], radius=12, fill=p["card"],
                            outline=p["accent2"], width=2)
        g_bloom(d, 842, 664 + oy, 40, p["accent2"], 2)
        T(d, 898, 672 + oy, "开花 · 木槿（稀有）", f["uib"], p["text"])
        T(d, 898, 698 + oy, "已永久留在花园，不会凋谢", f["small"], p["dim"])
    return img


# ---------------------------------------------------------------- 方向 C · 铸字工坊

def render_foundry(stage=8, anim=None):
    a = dict(filled=None, sample=1.0, toast=1.0, coined=None, count="1,204 字")
    if anim:
        a.update(anim)
    p = dict(PALETTES["foundry"])
    f = fonts("foundry")
    coined = {1: 96, 8: 1284, 20: 4780}[stage]
    if a["coined"] is not None:
        coined = a["coined"]
    if stage == 1:
        p["accent"] = "#8A7A63"
        p["accent2"] = "#5A6672"
    img, d = chrome("foundry", p)

    rail_icons(d, p, "foundry")
    header(d, p, f, title="字盘")

    rows = [
        (0, "tray", "字样档案", ""),
        (1, "type", "校样 03.md", ""),
        (1, "type", "字盘清单.md", ""),
        (1, "rune", "铸字规程.md", ""),
        (1, "frame", "铅字试印.png", ""),
    ][: 3 if stage == 1 else 5]
    tree(d, p, f, rows, selected=1)

    # 字盘网格
    cy = 588
    d.rounded_rectangle([72, cy, 314, cy + 158], radius=12, fill=p["card"], outline=p["line"])
    T(d, 88, cy + 14, "字盘 · 第一批", f["uib"], p["accent"])
    T_mix(d, 298, cy + 10, f"{coined:,} 枚", f["num"], f["ui"], p["dim"], align="right")
    filled = a["filled"] if a["filled"] is not None else {1: 3, 8: 17, 20: 24}[stage]
    for i in range(24):
        gx, gy = 88 + (i % 8) * 28, cy + 44 + (i // 8) * 26
        d.rounded_rectangle([gx, gy, gx + 20, gy + 18], radius=4,
                            fill=p["accent"] if i < filled else None,
                            outline=p["line"] if i >= filled else None, width=2)
    T(d, 88, cy + 132, "下一枚解锁：标题字体「汇文明朝」", f["small"], p["dim"])

    tabbar(d, p, f, "type", "校样 03")
    split_panes(d, p)

    src = [
        "# 字盘校样 03", "铅字：永 · 字 · 印 · 刷",
        f"铸字 {coined:,} 枚 / 1,500", "> 集满字盘解锁标题字体",
        "字距 12 · 行距 24", "压印力度 0.72",
    ]
    y = 78
    for i, text in enumerate(src):
        T_mix(d, 360, y, text, f["code"], f["body"], p["text"] if i < 3 else p["dim"])
        y += 32

    # 试印样张
    sy = int((1 - a["sample"]) * -120)
    d.rounded_rectangle([852, 66 + sy, 1264, 400 + sy], radius=12, fill=p["paper"])
    T(d, 884, 96 + sy, "随手 · 试印样张", f["small"], p["ink"])
    T(d, 884, 130 + sy, "永字印刷", f["title"], p["ink"])
    d.line([(884, 186 + sy), (1232, 186 + sy)], fill="#C9C4B8")
    T(d, 884, 202 + sy, f"铅字 {coined:,} 枚 · 第 03 批", f["body"], p["ink"])
    T(d, 884, 234 + sy, "铸字人：苏子夜", f["body"], p["ink"])
    for i, ch in enumerate("永字八法"):
        d.rounded_rectangle([884 + i * 44, 280 + sy, 920 + i * 44, 316 + sy], radius=6, fill="#DDD8CC")
        T(d, 902 + i * 44, 288 + sy, ch, f["body"], p["ink"], anchor="mt")
    T(d, 884, 344 + sy, "每写 1,000 字 → 铸一枚新铅字", f["small"], "#6E6A62")

    # 字模抽屉
    d.rounded_rectangle([852, 424, 1264, 620], radius=12, fill=p["card"], outline=p["line"])
    T(d, 872, 440, "字模抽屉", f["uib"], p["accent"])
    for i in range(3):
        for j in range(8):
            gx, gy = 872 + j * 48, 476 + i * 46
            unlocked = (i * 8 + j) < {1: 4, 8: 15, 20: 22}[stage]
            d.rounded_rectangle([gx, gy, gx + 34, gy + 34], radius=6,
                                fill=p["card2"], outline=p["accent"] if unlocked else p["line"], width=2)
            if unlocked:
                chars = "永字八法铸铅印校样盘活全"
                T(d, gx + 17, gy + 17, chars[(i * 8 + j) % len(chars)], f["ui"], p["accent"], anchor="mm")

    # 状态栏
    d.rounded_rectangle([344, 778, 448, 800], radius=11, fill=p["accent"])
    T_mix(d, 396, 781, "铸字工", f["num"], f["ui"], p["ink"], align="center")
    d.rounded_rectangle([460, 783, 700, 795], radius=6, fill=p["card2"])
    d.rounded_rectangle([460, 783, 460 + int(240 * min(1, coined / 1500)), 795], radius=6, fill=p["accent"])
    T_mix(d, 712, 774, f"{coined:,} / 1,500 枚", f["num"], f["ui"], p["dim"])
    T(d, 900, 780, "本批校样：字距 12 · 行距 24", f["ui"], p["accent2"])
    statusbar_static(d, p, f, f"已保存 · {a['count']}")

    if stage > 1 and a["toast"] > 0:
        oy = int((1 - a["toast"]) * 46)
        d.rounded_rectangle([826, 654 + oy, 1272, 730 + oy], radius=12, fill=p["card"],
                            outline=p["accent"], width=2)
        g_type(d, 842, 664 + oy, 40, p["accent"], 2)
        T(d, 898, 672 + oy, "解锁 · 标题字体「汇文明朝」", f["uib"], p["text"])
        T(d, 898, 698 + oy, "立即应用于标题与预览", f["small"], p["dim"])
    return img


# ---------------------------------------------------------------- 页面组装

def direction_page(win_factory, out, kind, name, en, tagline, blocks, stage_names):
    p = PALETTES[kind]
    W, H = 1840, 1500
    img, d = page(W, H)
    f = fonts("garden")

    d.rounded_rectangle([48, 34, 58, 92], radius=5, fill=p["accent"])
    T(d, 76, 36, f"游戏化主题方向 · {name}", fonts("guild")["title"], "#EFF4FF")
    T(d, 78, 84, en, F(MENLO, 13, 1), p["accent"])
    T(d, 78, 104, tagline, F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline=p["accent"])
    T(d, W - 189, 68, "待人工审核 · 不进入主题列表", F(HIRA, 13), p["accent"], anchor="mm")

    win = win_factory(8)
    paste_win(img, win, 48, 150)

    # 右侧说明栏
    x0 = 1400
    y0 = 150
    for i, (title, lines) in enumerate(blocks):
        h = 56 + len(lines) * 26
        d.rounded_rectangle([x0, y0, W - 48, y0 + h], radius=12, fill="#141A24", outline="#243041")
        T(d, x0 + 18, y0 + 14, title, F(HIRA, 15, 2), p["accent"])
        for j, line in enumerate(lines):
            T(d, x0 + 18, y0 + 44 + j * 26, line, F(HIRA, 13), "#B9C6DC")
        y0 += h + 14

    # 三阶形态
    ty = 1000
    T(d, 48, ty, "主题形态进化 · 同一套主题的三种形态（写作业绩解锁）", F(HIRA, 16, 2), "#DCE6FF")
    for i, st in enumerate((1, 8, 20)):
        mini = win_factory(st)
        scale = 0.37
        paste_win(img, mini, 48 + i * 515, ty + 44, scale=scale, radius=8, shadow=False)
        d.rounded_rectangle([48 + i * 515, ty + 44, 48 + i * 515 + 481, ty + 340], radius=8,
                            outline="#2A3648", width=1)
        T(d, 48 + i * 515, ty + 356, stage_names[i], F(HIRA, 14, 2), "#E7EEF9")
        T(d, 48 + i * 515, ty + 380, {1: "初始形态 · 功能完整、装饰克制",
                                      8: "成长形态 · 通用展示",
                                      20: "完全体 · 彩蛋与特效全开"}[st], F(HIRA, 12), "#8EA0BC")

    T(d, 48, H - 34, "进度完全本地计算（字数 / 保存 / 连更），不联网；动画尊重系统「减少动态效果」。",
      F(HIRA, 13), "#6F7E96")
    img.save(out)
    return out


def overview(out):
    W, H = 1840, 1320
    img, d = page(W, H)
    f16 = F(HIRA, 16, 2)
    f13 = F(HIRA, 13)
    T(d, 48, 34, "游戏化主题 · 三个方向", fonts("guild")["title"], "#EFF4FF")
    T(d, 50, 84, "主题不只是皮肤：写作业绩会推进主题自带的玩法，并解锁形态、称号、装饰与彩蛋。",
      F(HIRA, 15), "#93A3BE")

    items = [
        (render_guild(8), "A · 冒险者公会", "GUILD HALL",
         "写作 = 接委托 / 攒 XP / 升称号，完结长文 = 击败 Boss",
         ["每篇文档 = 一张委托卡（目标字数 / 截止日期）",
          "完结长文掉落成就与铭牌，大厅里立起你的纪念像",
          "字体 明朝宋 · 思源宋 · JetBrains Mono ／ 图标 盾匣 · 卷轴 · 符文石",
          "彩蛋 连更 7 天旗帜镀金、满级布告板换成王城通告"],
         ["#1B1410", "#221A13", "#D9A441", "#C4552F", "#EFE0BE"]),
        (render_garden(8), "B · 纸上花园", "PAPER GARDEN",
         "写作 = 浇水，每篇文档养一株植物，开花后永久收藏",
         ["新建文档 = 播种，输入与保存 = 浇水；闲置 7 天休眠",
          "里程碑开花，稀有花色随机出现，花园随季节换装",
          "字体 悦宋 · 苹方 · Menlo ／ 图标 花盆 · 叶片 · 花",
          "彩蛋 连更 30 天引来蝴蝶与萤火（可静置）"],
         ["#F8F4EA", "#F3EEE2", "#5F8468", "#D4899F", "#DFAE3A"]),
        (render_foundry(8), "C · 铸字工坊", "TYPE FOUNDRY",
         "写作 = 铸铅字，集满字盘直接解锁主题专属字体与动效",
         ["每 1,000 字铸一枚铅字，字盘逐格填满",
          "集满一批 → 解锁主题资产（字体 / 图标 / 动效）",
          "字体 汇文明朝 · 宋体 · Menlo ／ 图标 字匣 · 铅字块 · 字盘",
          "彩蛋 印刷机印出带名字的试印样张"],
         ["#15171B", "#1A1D22", "#C08A4A", "#5B8DB8", "#EFEDE7"]),
    ]
    for i, (win, title, en, tag, lines, colors) in enumerate(items):
        y = 136 + i * 322
        d.rounded_rectangle([40, y - 18, 1800, y + 296], radius=14, fill="#111722", outline="#1F2937")
        paste_win(img, win, 62, y, scale=0.30, radius=7, shadow=False)
        d.rounded_rectangle([62, y, 62 + 390, y + 240], radius=7, outline="#2A3648", width=1)
        T(d, 486, y + 2, title, F(HIRA, 20, 2), "#EFF4FF")
        T(d, 488, y + 36, en, F(MENLO, 11, 1), "#6E7E96")
        T(d, 488, y + 60, tag, f13, "#B9C6DC")
        for j, line in enumerate(lines):
            T(d, 488, y + 94 + j * 24, line, F(HIRA, 12), "#8FA0BB")
        for k, col in enumerate(colors):
            bx = 1500 + k * 58
            d.rounded_rectangle([bx, y + 8, bx + 44, y + 60], radius=8, fill=col, outline="#2A3648")
        T(d, 1500, y + 70, "主题色板", F(HIRA, 11), "#5F6E86")
    d.rounded_rectangle([48, H - 150, 1792, H - 48], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, H - 132, "共同规则（写进主题审核规范）", f16, "#7FD1C0")
    T(d, 70, H - 100, "① 专属玩法：主题必须声明一条「写作 → 反馈 → 解锁」循环，纯换色不通过。",
      f13, "#B9C6DC")
    T(d, 70, H - 76, "② 专属资产：字体 / 语义图标 / 动效 / 彩蛋 与玩法对齐，进度解锁的资产要在主题包内静态声明。",
      f13, "#B9C6DC")
    T(d, 70, H - 52, "③ 不卡：进度本地计算、增量更新；动画只用 opacity / transform，尊重「减少动态效果」。",
      f13, "#B9C6DC")
    img.save(out)
    return out


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/game")
    outdir.mkdir(parents=True, exist_ok=True)
    direction_page(
        render_guild, outdir / "guild.png", "guild", "冒险者公会", "GUILD HALL",
        "每一篇文档都是一张委托卡；写完它，你会升级、得到称号，并在公会大厅留下痕迹。",
        [
            ("专属玩法", ["· 每篇文档 = 一张委托卡（目标字数 / 截止）",
                          "· 字数、保存、连更 → 经验与声望",
                          "· 完结长文 = 击败 Boss，掉落成就与铭牌"]),
            ("专属资产", ["· 字体：明朝宋标题 / 思源宋正文 / Mono 代码",
                          "· 图标：盾匣=文件夹、卷轴=Markdown、符文石=代码…",
                          "· 动效：火把呼吸、经验条涨满、成就横幅滑入"]),
            ("彩蛋", ["· 连续 7 天：公会旗帜镀金",
                      "· 累计 10 万字：大厅立起你的纪念像",
                      "· 满级：布告板换成王城通告"]),
        ],
        ["Lv.1 · 起始形态", "Lv.12 · 成长形态", "Lv.27 · 完全体"],
    )
    direction_page(
        render_garden, outdir / "garden.png", "garden", "纸上花园", "PAPER GARDEN",
        "写作就是浇水。每篇文档养一株植物，里程碑开花，花开之后永久留在你的花园里。",
        [
            ("专属玩法", ["· 新建文档 = 播种，输入与保存 = 浇水",
                          "· 字数决定生长值；连更让植物升级",
                          "· 闲置 7 天休眠，回来写几句就复苏"]),
            ("专属资产", ["· 字体：悦宋标题 / 苹方正文 / Menlo 代码",
                          "· 图标：花盆=文件夹、叶片=Markdown、花=文档…",
                          "· 动效：风吹叶摆、开花绽放、光标处留下水痕"]),
            ("彩蛋", ["· 稀有花色（木槿 / 蓝铃）随机出现",
                      "· 连续 30 天：引来蝴蝶与萤火",
                      "· 100 朵花：花园角落长出一棵老树"]),
        ],
        ["萌芽 · 窗台小盆栽", "花期 · 阳台庭院", "满园 · 四季花园"],
    )
    direction_page(
        render_foundry, outdir / "foundry.png", "foundry", "铸字工坊", "TYPE FOUNDRY",
        "你写的每个字都会铸成一枚铅字。集满字盘，直接解锁主题的专属字体、图标与动效。",
        [
            ("专属玩法", ["· 每 1,000 字铸一枚铅字，字盘逐格填满",
                          "· 集满一批 → 解锁主题资产（字体 / 图标 / 动效）",
                          "· 校样参数随写作习惯变化并写回主题"]),
            ("专属资产", ["· 字体：汇文明朝标题 / 宋体正文 / Menlo 代码",
                          "· 图标：字匣=文件夹、铅字块=文档、字盘=目录…",
                          "· 动效：铅字落盘、油墨晕开、压印闪光"]),
            ("彩蛋", ["· 字盘集满：印刷机咔哒印出带名字的试印样张",
                      "· 出现错字：纸面浮出一枚倒置铅字（可关闭）",
                      "· 满 5,000 枚：抽屉换成黄铜字模"]),
        ],
        ["手工作坊 · 单枚铸字", "排字车间 · 字盘初成", "铅印厂 · 完全体"],
    )
    overview(outdir / "overview.png")
    for n in ("guild", "garden", "foundry", "overview"):
        print(outdir / f"{n}.png")


if __name__ == "__main__":
    main()
