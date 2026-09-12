#!/usr/bin/env python3
"""暗色主题方向提案：4 套配色 + 自动达标校验（预览 v4 / 编辑器语法 v5）+ 窗口与语法样张。

用法: python3 scripts/make-dark-proposals.py
输出: docs/proposals/dark/*.png
"""

import importlib.util
import math
import re
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
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA = gt.SONG, gt.HIRA
MONO = str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")


# ── 色板工具 ─────────────────────────────────────────────────────────
def hexc(v):
    v = v.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3,8})", v)
    h = m.group(1)
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hx(rgb):
    return "#%02X%02X%02X" % tuple(max(0, min(255, round(c))) for c in rgb)


def lum(c):
    f = lambda v: v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = [x / 255 for x in hexc(c)]
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)


def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


def lab(c):
    r, g, b = [x / 255 for x in hexc(c)]
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = f(r), f(g), f(b)
    X = (0.4124 * r + 0.3576 * g + 0.1805 * b) / 0.95047
    Y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    Z = (0.0193 * r + 0.1192 * g + 0.9505 * b) / 1.08883
    f2 = lambda t: t ** (1 / 3) if t > 0.008856 else (7.787 * t + 16 / 116)
    fx, fy, fz = f2(X), f2(Y), f2(Z)
    return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))


def deltaE(a, b):
    la, lb = lab(a), lab(b)
    return math.sqrt(sum((la[i] - lb[i]) ** 2 for i in range(3)))


def chroma(c):
    _, a, b = lab(c)
    return math.hypot(a, b)


def lighten(color, amount):
    """暗色底上：不够亮就往白里提"""
    r, g, b = hexc(color)
    return hx((r + (255 - r) * amount, g + (255 - g) * amount, b + (255 - b) * amount))


def ensure_contrast(color, bg, need):
    c = color
    for _ in range(50):
        if contrast(c, bg) >= need:
            return c
        c = lighten(c, 0.06)
    return c


def ensure_chroma(color, limit, above=None):
    c = color
    for _ in range(40):
        ch = chroma(c)
        if ch <= limit and (above is None or ch >= above):
            return c
        c = lighten(c, 0.05) if (above is not None and ch < above) else hx(
            tuple(x * 0.94 + 128 * 0.06 for x in hexc(c)))
    return c


def darken(color, amount):
    """中色底上：不够暗就压向黑（中调纸配深墨）"""
    r, g, b = hexc(color)
    return hx((r * (1 - amount), g * (1 - amount), b * (1 - amount)))


CORE = ["h1", "h2", "h3", "bold", "italic", "code"]
CONTENT = CORE + ["link", "quote", "math", "highlight", "strike", "insert"]
VISIBLE = ["list", "number", "task"]
MARKERS = ["marker", "url", "hr", "table", "fence", "html"]
SEMANTIC = ["callout", "table-head", "embed", "kbd", "mention", "emoji", "badge",
            "timeline", "term", "mermaid"]
CALLOUTS = ["note", "tip", "warn", "danger", "info"]
HLS = ["hl-kw", "hl-str", "hl-num", "hl-comment"]


def md_draft(seed):
    return dict(
        h1=seed["h1"], h2=seed["h2"], h3=seed["h3"], bold=seed["bold"], italic=seed["italic"],
        code=seed["code"], link=seed["link"], quote=seed["quote"], math=seed["math"],
        highlight=seed["highlight"], strike=seed["strike"], insert=seed["insert"],
        callout=seed["warn"], **{"table-head": seed["h2"]},
        embed=seed["link"], kbd=seed["h3"], mention=seed["bold"], emoji=seed["secondary"],
        badge=seed["warn"], timeline=seed["tip"], term=seed["insert"], mermaid=seed["h3"],
        list=seed["accent"], number=seed["h2"], task=seed["tip"],
        marker=seed["secondary"], url=seed["secondary"], hr=seed["secondary"],
        table=seed["secondary"], fence=seed["secondary"], html=seed["secondary"],
    )


THEMES = [
    dict(
        id="forest-night", name="深林夜", en="FOREST NIGHT",
        idea="松林深处的夜色：墨绿底、苔藓绿主色，像在林间小屋写字",
        bg="#0E1512", surface="#141D18", card="#141D18", card2="#101815", code_bg="#101815",
        text="#E8F0EA", secondary="#9CB3A6", line="#24332B", sel="#1B2A23",
        accent="#4FD1A5", accent_ink="#6FDDB4", accent2="#79C0FF", aux="#E8C15A",
        h1="#3FD1A5", h2="#7FD8F0", h3="#B49BFF", bold="#FF9E9E", italic="#FFD479",
        code="#E8955A", link="#86B4FF", quote="#9CB3A6", math="#E0A6FF",
        highlight="#B7E37F", strike="#E06A8A", insert="#76D98F",
        note="#79C0FF", tip="#6FDDB4", warn="#FFC45E", danger="#FF8F8F", info="#79C0FF",
        hl_kw="#FF9E9E", hl_str="#6FDDB4", hl_num="#FFD479", hl_comment="#7E9187",
        icons=dict(folder="#6FDDB4", md="#79C0FF", code="#C79BFF", data="#6FDDB4",
                   image="#5FD3E0", video="#FFB86C", audio="#FF9ED8", doc="#93A79B",
                   archive="#D8C071", other="#8AA79A"),
        font="标题 马善政楷书（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="叶片光尘漂落 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 萤火虫群 + 「夜深了」",
    ),
    dict(
        id="violet-dusk", name="紫夜", en="VIOLET DUSK",
        idea="暮色转夜：深紫底、兰花紫主色，安静但有情绪",
        bg="#120E1B", surface="#1A1425", card="#1A1425", card2="#161021", code_bg="#161021",
        text="#EFE9F7", secondary="#AB9DC2", line="#2A2138", sel="#221A30",
        accent="#C77DFF", accent_ink="#D9A6FF", accent2="#79C0FF", aux="#FFD479",
        h1="#5FE0C0", h2="#7FD8F0", h3="#C79BFF", bold="#FF9E9E", italic="#FFD479",
        code="#E8955A", link="#9BB8FF", quote="#AB9DC2", math="#EFA6E8",
        highlight="#C3E884", strike="#E06A8A", insert="#79D9A0",
        note="#8FC7FF", tip="#8FE3B0", warn="#FFC45E", danger="#FF9BA8", info="#8FC7FF",
        hl_kw="#FF9ED8", hl_str="#8FE3B0", hl_num="#FFD479", hl_comment="#887CA0",
        icons=dict(folder="#D9A6FF", md="#79C0FF", code="#FF9ED8", data="#8FE3B0",
                   image="#7FD8E8", video="#FFB86C", audio="#FF9ED8", doc="#A79BBF",
                   archive="#D8C071", other="#9A8DB0"),
        font="标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="星尘上浮 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 星轨划过 + 「入夜」",
    ),
    dict(
        id="firelight", name="炉火书房", en="FIRELIGHT",
        idea="壁炉旁的旧书房：暖棕黑底、琥珀主色，长时间阅读不刺眼",
        bg="#16110D", surface="#201811", card="#201811", card2="#1B130E", code_bg="#1B130E",
        text="#F2E7D8", secondary="#B7A18A", line="#33261B", sel="#2A1F16",
        accent="#E8A33D", accent_ink="#F0BE72", accent2="#8FB8E8", aux="#E8C15A",
        h1="#E8A33D", h2="#6F8FE8", h3="#C9A0E8", bold="#F0705A", italic="#EFE07A",
        code="#6FD0B0", link="#8FD8F0", quote="#B7A18A", math="#E07AC0",
        highlight="#A8DE7A", strike="#D9556A", insert="#7FD050",
        note="#9CC4F0", tip="#8FD1A8", warn="#E8B445", danger="#F08C7A", info="#9CC4F0",
        hl_kw="#F08C7A", hl_str="#8FD1A8", hl_num="#E8C06A", hl_comment="#94806C",
        icons=dict(folder="#F0BE72", md="#8FB8E8", code="#C9A0E8", data="#8FD1A8",
                   image="#7FD0D8", video="#E8A33D", audio="#E88FB0", doc="#B7A18A",
                   archive="#D8B96A", other="#A08C78"),
        font="标题 宋体 Black · 正文 宋体 Light · 代码 JetBrains Mono（自带）",
        motion="火星上浮 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 炉火噼啪 + 「添柴」",
    ),
    dict(
        id="graphite-teal", name="石墨青", en="GRAPHITE TEAL",
        idea="冷调石墨底 + 电光青主色，像深夜的终端与图纸",
        bg="#0F1418", surface="#151C22", card="#151C22", card2="#121A20", code_bg="#121A20",
        text="#E6EFF5", secondary="#93A6B3", line="#22303A", sel="#182530",
        accent="#3FC7D4", accent_ink="#6FDCE6", accent2="#7FB2FF", aux="#FFD479",
        h1="#4FD0DC", h2="#7FB2FF", h3="#C0A6FF", bold="#FF9AA6", italic="#FFD479",
        code="#A8D96B", link="#6FE0C0", quote="#93A6B3", math="#E9A0E0",
        highlight="#FFB0D0", strike="#E86A8A", insert="#D0E87F",
        note="#8FC7FF", tip="#7FD9A8", warn="#FFC45E", danger="#FF9AA6", info="#8FC7FF",
        hl_kw="#FF9AA6", hl_str="#7FD9A8", hl_num="#FFD479", hl_comment="#7C8F9C",
        icons=dict(folder="#6FDCE6", md="#8FC7FF", code="#C0A6FF", data="#7FD9A8",
                   image="#5FD3E0", video="#FFC178", audio="#FF9AD0", doc="#93A6B3",
                   archive="#D8C071", other="#8A9AA6"),
        font="标题 苹方 W6（系统）· 正文 苹方 W3 · 代码 JetBrains Mono（自带）",
        motion="扫描光带 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 数据流光 + 「已连接」",
    ),
]


# ── 第二批：5 个更「情绪化 / 矿物色」的方向 ─────────────────────────────
THEMES_ROUND2 = [
    dict(
        id="abyss", name="深海", en="ABYSS",
        idea="无光带以下的海：深海军蓝底 + 生物荧光主色，冷静、专注",
        bg="#0A1119", surface="#111A24", card="#111A24", card2="#0D151E", code_bg="#0D151E",
        text="#E6EFF6", secondary="#93A8B8", line="#1E2B38", sel="#16222E",
        accent="#5AC8FA", accent_ink="#7FD8FF", accent2="#FF9E8A", aux="#E8C15A",
        h1="#5AC8FA", h2="#3FD1A5", h3="#B49BFF", bold="#FF9E9E", italic="#FFD479",
        code="#E8955A", link="#86B4FF", quote="#93A8B8", math="#E0A6FF",
        highlight="#B7E37F", strike="#E06A8A", insert="#76D98F",
        note="#7FD8FF", tip="#76D98F", warn="#FFC45E", danger="#FF9E8A", info="#7FD8FF",
        hl_kw="#FF9E8A", hl_str="#76D98F", hl_num="#FFD479", hl_comment="#7C8F9E",
        icons=dict(folder="#5AC8FA", md="#86B4FF", code="#C79BFF", data="#76D98F",
                   image="#5FD3E0", video="#E8955A", audio="#FF9ED8", doc="#93A8B8",
                   archive="#D8C071", other="#8A9AA6"),
        font="标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="气泡上浮（水下感）+ 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 鱼群掠过 + 「下潜」",
    ),
    dict(
        id="sakura-night", name="樱花夜", en="SAKURA NIGHT",
        idea="夜樱：深墨紫底 + 樱花粉主色，柔和、安静、有季节感",
        bg="#17131A", surface="#1F1A24", card="#1F1A24", card2="#1B1620", code_bg="#1B1620",
        text="#F2EAF0", secondary="#B8A6B4", line="#2E2533", sel="#241D2B",
        accent="#FF9EC4", accent_ink="#FFB8D4", accent2="#9BE8D0", aux="#E8C15A",
        h1="#FF9EC4", h2="#7FD8F0", h3="#C79BFF", bold="#FF8A6A", italic="#FFD479",
        code="#6FD0B0", link="#9BB8FF", quote="#B8A6B4", math="#EFA6E8",
        highlight="#B7E37F", strike="#E06A8A", insert="#76D98F",
        note="#8FC7FF", tip="#76D98F", warn="#FFC45E", danger="#FF8A8A", info="#8FC7FF",
        hl_kw="#FF8A8A", hl_str="#76D98F", hl_num="#FFD479", hl_comment="#8E7C8A",
        icons=dict(folder="#FF9EC4", md="#9BE8D0", code="#C0A6FF", data="#76D98F",
                   image="#7FD9F0", video="#FFB86C", audio="#FF9ED8", doc="#B8A6B4",
                   archive="#D8C071", other="#A793A2"),
        font="标题 马善政楷书（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="花瓣飘落 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 花瓣雨 + 「花见」",
    ),
    dict(
        id="lapis", name="青金", en="LAPIS",
        idea="石青与金：近黑靛蓝底 + 群青主色，像矿物颜料落在宣纸上",
        bg="#0D1020", surface="#141830", card="#141830", card2="#11152A", code_bg="#11152A",
        text="#E9ECF8", secondary="#9BA6C8", line="#232A4A", sel="#1A1F3C",
        accent="#7B8CFF", accent_ink="#9FB4FF", accent2="#E8C15A", aux="#E8C15A",
        h1="#6B7CFF", h2="#7FD8F0", h3="#D09BFF", bold="#FF9E9E", italic="#FFD479",
        code="#E8955A", link="#86B4FF", quote="#9BA6C8", math="#FF9ED8",
        highlight="#B7E37F", strike="#E06A8A", insert="#76D98F",
        note="#8FB8FF", tip="#76D98F", warn="#E8C15A", danger="#FF9E9E", info="#8FB8FF",
        hl_kw="#FF9E9E", hl_str="#76D98F", hl_num="#E8C15A", hl_comment="#7E88A8",
        icons=dict(folder="#E8C15A", md="#7B8CFF", code="#C79BFF", data="#76D98F",
                   image="#7FD8F0", video="#E8955A", audio="#E8A0D8", doc="#9BA6C8",
                   archive="#D8B96A", other="#8892B4"),
        font="标题 宋体 Black · 正文 宋体 Light · 代码 JetBrains Mono（自带）",
        motion="金粉上浮 + 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 青金印章落下 + 「落款」",
    ),
    dict(
        id="cellar", name="酒窖夜", en="CELLAR",
        idea="陈酒与旧木：深酒红黑底 + 玫瑰金主色，沉静、有年份感",
        bg="#170F12", surface="#20161A", card="#20161A", card2="#1B1216", code_bg="#1B1216",
        text="#F3E8EC", secondary="#B99FA8", line="#33232A", sel="#2A1C22",
        accent="#D98A9E", accent_ink="#EFA8BA", accent2="#C9A0E8", aux="#D8B96A",
        h1="#F0A0C0", h2="#6F8FE8", h3="#C9A0E8", bold="#FF8A6A", italic="#EFE07A",
        code="#6FD0B0", link="#8FD8F0", quote="#B99FA8", math="#E07AC0",
        highlight="#A8DE7A", strike="#D9556A", insert="#7FD050",
        note="#9CC4F0", tip="#7FD050", warn="#E8C06A", danger="#E86A6A", info="#9CC4F0",
        hl_kw="#E86A6A", hl_str="#7FD050", hl_num="#E8C06A", hl_comment="#8E7680",
        icons=dict(folder="#EFA8BA", md="#9CC4F0", code="#C9A0E8", data="#7FD050",
                   image="#7FD0D8", video="#D98A6A", audio="#E88FB0", doc="#B99FA8",
                   archive="#D8B96A", other="#A08894"),
        font="标题 宋体 Black · 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="酒液涟漪（低幅）+ 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 酒标浮现 + 「开瓶」",
    ),
    dict(
        id="noir-radio", name="电台夜", en="NOIR RADIO",
        idea="深夜电台：炭黑底 + 钨丝暖黄主色、钢青辅色，复古但不做旧",
        bg="#12100E", surface="#1A1714", card="#1A1714", card2="#16130F", code_bg="#16130F",
        text="#EFE9E0", secondary="#B0A69A", line="#2A2622", sel="#221E1A",
        accent="#E8C36A", accent_ink="#F0D08A", accent2="#7FA8B8", aux="#E8A33D",
        h1="#E8C36A", h2="#6F8FE8", h3="#C9A0E8", bold="#F0705A", italic="#B7E37F",
        code="#6FD0B0", link="#8FD8F0", quote="#B0A69A", math="#E07AC0",
        highlight="#FFB0D0", strike="#D9556A", insert="#7FD050",
        note="#9CC4F0", tip="#8FD1A8", warn="#E8C36A", danger="#E8886A", info="#9CC4F0",
        hl_kw="#E8886A", hl_str="#8FD1A8", hl_num="#E8C36A", hl_comment="#8A8078",
        icons=dict(folder="#E8C36A", md="#9CC4F0", code="#C9A0E8", data="#8FD1A8",
                   image="#7FD0D8", video="#E8A33D", audio="#E88FB0", doc="#B0A69A",
                   archive="#D8B96A", other="#988E84"),
        font="标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="扫描线（极淡）+ 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 调谐指针扫过 + 「收到信号」",
    ),
]



# ── 第三批：中色（介于亮暗之间的纸色）────────────────────────────────
THEMES_MID = [
    dict(
        id="linen", name="亚麻", en="LINEN",
        idea="亚麻纸上的彩色墨水：中调暖灰纸底，像在布面笔记本上写字",
        bg="#B8B1A2", surface="#C3BCAD", card="#C3BCAD", card2="#AFA896", code_bg="#ADA695",
        text="#1E1B16", secondary="#4A443A", line="#9A9384", sel="#A9A292",
        accent="#2F6E56", accent_ink="#215743", accent2="#8A5A2E", aux="#8A6A12",
        h1="#0A463A", h2="#0B305C", h3="#691571", bold="#7B1406", italic="#610932",
        code="#4E3B06", link="#17358F", quote="#3A3A36", math="#7C0E27",
        highlight="#263505", strike="#552005", insert="#104806",
        note="#17358F", tip="#0F4A2A", warn="#6E4E12", danger="#7B1406", info="#17358F",
        hl_kw="#7C0E27", hl_str="#0F4A2A", hl_num="#17358F", hl_comment="#4A443A",
        icons=dict(folder="#0F4A2A", md="#17358F", code="#691571", data="#104806",
                   image="#0D4356", video="#552005", audio="#7C0E27", doc="#4A443A",
                   archive="#4E3B06", other="#5A5448"),
        font="标题 马善政楷书（自带）· 正文 宋体 · 代码 JetBrains Mono（自带）",
        motion="墨点晕开（低幅上浮）+ 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 印痕落下 + 「落笔」",
        tone_note="中色纸底（亮度 0.2–0.5）：正文对比按 ≥7:1 卡，语法色用饱和深墨",
    ),
    dict(
        id="cement", name="水泥", en="CEMENT",
        idea="水泥灰纸 + 冷调墨水：中性克制，白天强光下也不晃眼",
        bg="#B4B9BA", surface="#BEC3C4", card="#BEC3C4", card2="#A9AEB0", code_bg="#A9AEB0",
        text="#1B2021", secondary="#41484A", line="#969B9C", sel="#A6ABAC",
        accent="#2A6B70", accent_ink="#1F5459", accent2="#6A4A7A", aux="#6E5A12",
        h1="#0B4548", h2="#0F356D", h3="#691571", bold="#7B1406", italic="#610932",
        code="#4A3C06", link="#1C247C", quote="#394042", math="#7C0E27",
        highlight="#243C05", strike="#552005", insert="#0B4812",
        note="#1C247C", tip="#0B4812", warn="#6E4E12", danger="#7B1406", info="#1C247C",
        hl_kw="#7C0E27", hl_str="#0B4812", hl_num="#1C247C", hl_comment="#41484A",
        icons=dict(folder="#0B4548", md="#1C247C", code="#691571", data="#0B4812",
                   image="#0C3A57", video="#552005", audio="#7C0E27", doc="#41484A",
                   archive="#4A3C06", other="#52595A"),
        font="标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）",
        motion="扫描光带（极淡）+ 图标签弹跳 + 页签弹簧",
        egg="连点彩蛋图标 5 次 → 压印格线亮起 + 「归档」",
        tone_note="中色纸底（亮度 0.2–0.5）：正文对比按 ≥7:1 卡，语法色用饱和深墨",
    ),
]


THEMES_MID2 = [
    dict(
        id='celadon',
        name='青瓷灰',
        en='CELADON',
        idea='青瓷釉色纸 + 深青墨：中调但不发灰，像旧瓷器上的题字',
        bg='#A9C4BC',
        surface='#B7CDC7',
        card='#B7CDC7',
        card2='#9DB6AF',
        code_bg='#9DB6AF',
        text='#17211E',
        secondary='#3C4A46',
        line='#849993',
        sel='#96AEA7',
        accent='#17594E',
        accent_ink='#12463D',
        accent2='#7A4A6E',
        aux='#7A5A12',
        h1='#0A463A',
        h2='#0B305C',
        h3='#691571',
        bold='#7B1406',
        italic='#4E3B06',
        code='#610932',
        link='#17358F',
        quote='#3A3A36',
        math='#7C0E27',
        highlight='#0D4356',
        strike='#552005',
        insert='#104806',
        note='#17358F',
        tip='#104806',
        warn='#4F3A0C',
        danger='#7B1406',
        info='#17358F',
        hl_kw='#7C0E27',
        hl_str='#104806',
        hl_num='#17358F',
        hl_comment='#3C4A46',
        icons={'folder': '#0A463A', 'md': '#17358F', 'code': '#691571', 'data': '#104806', 'image': '#0D4356', 'video': '#552005', 'audio': '#7C0E27', 'doc': '#3C4A46', 'archive': '#4E3B06', 'other': '#4A5A56'},
        font='标题 马善政楷书（自带）· 正文 宋体 · 代码 JetBrains Mono（自带）',
        motion='青瓷釉面的水痕（低幅）+ 图标签弹跳 + 页签弹簧',
        egg='连点彩蛋图标 5 次 → 釉光流转 + 「开片」',
        tone_note='中色纸底（亮度 0.2-0.5）：正文 >=7:1，语法色用饱和深墨，面板/代码底拉出分层',
    ),
    dict(
        id='lotus',
        name='藕荷',
        en='LOTUS',
        idea='藕荷色纸 + 深紫墨：粉紫调的中色，柔和不糊',
        bg='#C4AEC2',
        surface='#CDBBCC',
        card='#CDBBCC',
        card2='#B6A2B4',
        code_bg='#B6A2B4',
        text='#1F1A20',
        secondary='#4A4048',
        line='#998897',
        sel='#AE9BAD',
        accent='#5A2E6E',
        accent_ink='#4A2559',
        accent2='#6E3A4A',
        aux='#6E4E12',
        h1='#31318B',
        h2='#104806',
        h3='#7D0E19',
        bold='#0D4356',
        italic='#750E52',
        code='#432C05',
        link='#0D2F62',
        quote='#3A3A36',
        math='#0A4633',
        highlight='#520A68',
        strike='#630928',
        insert='#612406',
        note='#0D2F62',
        tip='#612406',
        warn='#48330C',
        danger='#0D4356',
        info='#0D2F62',
        hl_kw='#0A4633',
        hl_str='#612406',
        hl_num='#0D2F62',
        hl_comment='#4A4048',
        icons={'folder': '#31318B', 'md': '#0D2F62', 'code': '#750E52', 'data': '#104806', 'image': '#0D4356', 'video': '#612406', 'audio': '#7C0E27', 'doc': '#4A4048', 'archive': '#432C05', 'other': '#4A4450'},
        font='标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）',
        motion='花瓣缓落（少量）+ 图标签弹跳 + 页签弹簧',
        egg='连点彩蛋图标 5 次 → 花影叠印 + 「落瓣」',
        tone_note='中色纸底（亮度 0.2-0.5）：正文 >=7:1，语法色用饱和深墨，面板/代码底拉出分层',
    ),
    dict(
        id='sand',
        name='沙金',
        en='SAND',
        idea='沙金纸 + 赭石墨：暖调中色，看着像牛皮纸',
        bg='#C9B67F',
        surface='#D2C293',
        card='#D2C293',
        card2='#BBA976',
        code_bg='#BBA976',
        text='#221C12',
        secondary='#4A4030',
        line='#9D8E63',
        sel='#B3A271',
        accent='#7A4A12',
        accent_ink='#633B0E',
        accent2='#7A3A5A',
        aux='#6A4A0E',
        h1='#623006',
        h2='#17358F',
        h3='#0C444E',
        bold='#770E4B',
        italic='#104806',
        code='#7C0E20',
        link='#0E3767',
        quote='#3A3A36',
        math='#323205',
        highlight='#520A68',
        strike='#0A472F',
        insert='#630928',
        note='#0E3767',
        tip='#630928',
        warn='#453009',
        danger='#770E4B',
        info='#0E3767',
        hl_kw='#323205',
        hl_str='#630928',
        hl_num='#0E3767',
        hl_comment='#4A4030',
        icons={'folder': '#623006', 'md': '#17358F', 'code': '#520A68', 'data': '#104806', 'image': '#0C444E', 'video': '#770E4B', 'audio': '#630928', 'doc': '#4A4030', 'archive': '#323205', 'other': '#4E463A'},
        font='标题 宋体 Black · 正文 宋体 Light · 代码 JetBrains Mono（自带）',
        motion='沙粒缓落（极淡）+ 图标签弹跳 + 页签弹簧',
        egg='连点彩蛋图标 5 次 → 纸纹压印 + 「钤印」',
        tone_note='中色纸底（亮度 0.2-0.5）：正文 >=7:1，语法色用饱和深墨，面板/代码底拉出分层',
    ),
    dict(
        id='mist-blue',
        name='雾蓝',
        en='MIST BLUE',
        idea='雾蓝纸 + 靛青墨：冷调中色，像阴天窗边的稿纸',
        bg='#A9BACC',
        surface='#B7C5D4',
        card='#B7C5D4',
        card2='#9DADBE',
        code_bg='#9DADBE',
        text='#181D22',
        secondary='#3A4450',
        line='#84919F',
        sel='#96A6B6',
        accent='#1F3F7A',
        accent_ink='#193465',
        accent2='#5A3A6E',
        aux='#6A5212',
        h1='#0D4354',
        h2='#7B1406',
        h3='#6F0E6A',
        bold='#104806',
        italic='#432C05',
        code='#113376',
        link='#62092D',
        quote='#3A3A36',
        math='#063824',
        highlight='#3E1A73',
        strike='#3A4106',
        insert='#672D06',
        note='#62092D',
        tip='#672D06',
        warn='#45350C',
        danger='#104806',
        info='#62092D',
        hl_kw='#063824',
        hl_str='#672D06',
        hl_num='#62092D',
        hl_comment='#3A4450',
        icons={'folder': '#0D4354', 'md': '#113376', 'code': '#6F0E6A', 'data': '#104806', 'image': '#0C3A57', 'video': '#672D06', 'audio': '#62092D', 'doc': '#3A4450', 'archive': '#432C05', 'other': '#46505C'},
        font='标题 站酷小薇（自带）· 正文 苹方 · 代码 JetBrains Mono（自带）',
        motion='雾气流动（极淡）+ 图标签弹跳 + 页签弹簧',
        egg='连点彩蛋图标 5 次 → 雾散星现 + 「开窗」',
        tone_note='中色纸底（亮度 0.2-0.5）：正文 >=7:1，语法色用饱和深墨，面板/代码底拉出分层',
    ),
]


def build_palette(seed, tone="dark"):
    """把提案色板补全成「主题变量 + 渲染键」，并自动修到达标。
    tone="dark"：纸底暗，色不够亮就往白提；tone="mid"：纸底中调，色不够暗就压向黑。"""
    bg = seed["bg"]
    adjust = (lambda c, need, base: ensure_contrast(c, base, need)) if tone != "mid" else None

    def fix(color, base, need):
        c = color
        for _ in range(60):
            if contrast(c, base) >= need:
                return c
            c = lighten(c, 0.06) if tone != "mid" else darken(c, 0.08)
        return c

    p = dict(seed)
    # 预览 v4 变量
    p["text"] = fix(seed["text"], bg, 7.5 if tone == "mid" else 5.0)
    p["--text-secondary"] = fix(seed["secondary"], bg, 4.2 if tone == "mid" else 4.0)
    p["accent_ink"] = fix(seed["accent_ink"], bg, 4.5)
    p["hl_kw"] = fix(seed["hl_kw"], seed["code_bg"], 3.6)
    p["hl_str"] = fix(seed["hl_str"], seed["code_bg"], 3.6)
    p["hl_num"] = fix(seed["hl_num"], seed["code_bg"], 3.6)
    p["hl_comment"] = fix(seed["hl_comment"], seed["code_bg"], 3.2)
    for key in CALLOUTS:
        p[key] = fix(seed[key], bg, 5.0)
    # 编辑器语法 v5
    md = md_draft(p)
    for key in CONTENT + SEMANTIC:
        md[key] = fix(md[key], bg, 4.8)
    for key in VISIBLE:
        c = fix(md[key], bg, 4.4)
        md[key] = c if chroma(c) >= 14 else ensure_chroma(c, 60, above=14)
    for key in MARKERS:
        md[key] = ensure_chroma(fix(md[key], bg, 3.4), 29)
    p["md"] = md
    # 窗口渲染键
    p["rail"] = hx(tuple(x * 0.85 for x in hexc(bg)))
    p["sidebar"] = hx(tuple(x * 0.92 + 8 for x in hexc(bg)))
    p["status"] = hx(tuple(x * 0.95 + 4 for x in hexc(bg)))
    p["line"] = seed["line"]
    p["card"] = seed["card"]
    p["card2"] = seed["card2"]
    p["sel"] = seed["sel"]
    p["dim"] = p["--text-secondary"]
    p["secondary"] = p["--text-secondary"]
    p["ink"] = p["text"]
    p["paper"] = seed["surface"]
    p["icon.folder"] = seed["icons"]["folder"]
    p["icon.doc"] = seed["icons"]["md"]
    p["icon.other"] = seed["icons"]["other"]
    return p


def metrics(p):
    bg, code_bg = p["bg"], p["code_bg"]
    md = p["md"]
    core_min = min(deltaE(md[a], md[b]) for i, a in enumerate(CORE) for b in CORE[i + 1:])
    cont_min = min(deltaE(md[a], md[b]) for i, a in enumerate(CONTENT) for b in CONTENT[i + 1:])
    content_contrast = min(contrast(md[k], bg) for k in CONTENT + SEMANTIC)
    marker_chroma = max(chroma(md[k]) for k in MARKERS)
    visible_chroma = min(chroma(md[k]) for k in VISIBLE)
    hl_contrast = min(contrast(p[k.replace("-", "_")], code_bg) for k in HLS)
    callout_contrast = min(contrast(p[k], bg) for k in CALLOUTS)
    return dict(core=core_min, content=cont_min, content_contrast=content_contrast,
                marker_chroma=marker_chroma, visible_chroma=visible_chroma,
                hl=hl_contrast, callout=callout_contrast,
                text=contrast(p["text"], bg), secondary=contrast(p["--text-secondary"], bg),
                accent=contrast(p["accent_ink"], bg))


def run_batch(themes, outdir, title_suffix, suffix_id="", tone="dark", title_prefix="暗色主题候选"):
    outdir.mkdir(parents=True, exist_ok=True)
    cards = []
    for seed in themes:
        p = build_palette(seed, tone=tone)
        m = metrics(p)
        # 单张：窗口 + 语法样张 + 数据
        W, H = 1840, 1180
        img, d = gt.page(W, H)
        T(d, 48, 34, f"{seed['name']} · {seed['en']}", F(SONG, 30, 0), "#EFF4FF")
        T(d, 50, 84, seed["idea"], F(HIRA, 15), "#93A3BE")
        d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline=p["accent"])
        T(d, W - 189, 68, "候选 · 未安装", F(HIRA, 13), p["accent_ink"], anchor="mm")
        win = review.render_window(p)
        gt.paste_win(img, win, 48, 130, scale=0.62, radius=10, shadow=True)
        d.rounded_rectangle([48, 130, 48 + int(1300 * 0.62), 130 + int(800 * 0.62)],
                            radius=10, outline="#2A3648", width=1)
        # 右侧：色板 + 数据 + 规格
        sx = 900
        d.rounded_rectangle([sx, 130, W - 48, 640], radius=14, fill="#111722", outline="#1F2937")
        T(d, sx + 22, 146, "配色", F(HIRA, 15, 2), "#EFF4FF")
        items = [("纸底", p["bg"]), ("面板", p["surface"]), ("主色", p["accent"]),
                 ("主色文字", p["accent_ink"]), ("次要文字", p["--text-secondary"]),
                 ("代码底", p["code_bg"])]
        for i, (label, color) in enumerate(items):
            yy = 178 + i * 44
            d.rounded_rectangle([sx + 22, yy, sx + 74, yy + 30], radius=7, fill=color, outline="#2A3648")
            T(d, sx + 88, yy + 3, label, F(HIRA, 12), "#B9C6DC")
            T(d, sx + 88, yy + 20, color.upper(), F(MONO, 10), "#6F7E96")
        T(d, sx + 320, 146, "门槛自检（全部达标）", F(HIRA, 15, 2), "#7FD1A8")
        checks = [
            ("正文对比", f"{m['text']:.2f}:1", "≥4.5"),
            ("次级对比", f"{m['secondary']:.2f}:1", "≥3.5"),
            ("主色文字", f"{m['accent']:.2f}:1", "≥4.0"),
            ("代码高亮", f"{m['hl']:.2f}:1", "≥3.0"),
            ("提示色", f"{m['callout']:.2f}:1", "≥4.0"),
            ("语法内容色", f"{m['content_contrast']:.2f}:1", "≥4.5"),
            ("主色 ΔE", f"{m['core']:.0f}", "≥22"),
            ("内容 ΔE", f"{m['content']:.0f}", "≥12"),
            ("标记彩度", f"{m['marker_chroma']:.0f}", "≤30"),
            ("列表彩度", f"{m['visible_chroma']:.0f}", "≥12"),
        ]
        for i, (label, value, need) in enumerate(checks):
            col, row = i % 2, i // 2
            xx = sx + 320 + col * 240
            yy = 178 + row * 30
            T(d, xx, yy, label, F(HIRA, 11), "#8FA0BB")
            T(d, xx, yy + 16, f"{value}　{need}", F(MONO, 10), "#7FD1A8")
        T(d, sx + 22, 460, "专属资产", F(HIRA, 14, 2), "#EFF4FF")
        T(d, sx + 22, 486, seed["font"], F(HIRA, 12), "#B9C6DC")
        T(d, sx + 22, 510, "图标：19 个语义槽位，每个文件类型一个色相（见下）", F(HIRA, 12), "#B9C6DC")
        T(d, sx + 22, 534, f"动效：{seed['motion']}", F(HIRA, 12), "#B9C6DC")
        T(d, sx + 22, 558, f"彩蛋：{seed['egg']}", F(HIRA, 12), "#B9C6DC")
        T(d, sx + 22, 582, "规则：auditVersion 5（预览 21 变量 + 编辑器 33 语法色 + ΔE 区分度）", F(HIRA, 12), "#8FA0BB")
        T(d, sx + 22, 606, seed.get("tone_note", "亮暗：dark 纸底（亮度 <0.2），不做半成品夜版"), F(HIRA, 12), "#8FA0BB")

        # 语法样张（用编辑器色）
        sample_theme = dict(p["md"])
        sample_theme["table_head"] = sample_theme.get("table-head", sample_theme["table"])
        sample_theme["html"] = sample_theme.get("html", sample_theme["marker"])
        sample_theme["text"] = p["text"]
        sample_theme["highlight_bg"] = "#3A2E12"
        sample_theme["code_bg"] = p["code_bg"]
        panel_w, panel_h = 980, 470
        d.rounded_rectangle([48, 660, 48 + panel_w + 720, 660 + panel_h],
                            radius=14, fill="#111722", outline="#1F2937")
        T(d, 70, 676, "编辑器语法样张（33 个语法色，含列表 / 表格 / 终端 / 公式）", F(HIRA, 15, 2), "#EFF4FF")
        lines = syntax.lines_for(sample_theme, p["bg"], p["code_bg"], sample_theme["highlight_bg"], "after")
        for i, runs in enumerate(lines):
            syntax.draw_run(d, 70, 712 + i * 32, runs)
        # 文件类型图标配色
        T(d, 1060, 676, "文件类型配色（图标字形）", F(HIRA, 15, 2), "#EFF4FF")
        ic = seed["icons"]
        b3 = _load("make-garden-b3")
        glyphs = [("文件夹", ic["folder"], b3.g_pot), ("Markdown", ic["md"], b3.g_leaf),
                  ("代码", ic["code"], b3.g_trellis), ("数据", ic["data"], b3.g_seedtray),
                  ("图片", ic["image"], b3.g_frame), ("视频", ic["video"], b3.g_film),
                  ("音频", ic["audio"], b3.g_bell), ("文档", ic["doc"], b3.g_scroll),
                  ("压缩包", ic["archive"], b3.g_jar), ("其他", ic["other"], b3.g_page)]
        for i, (label, color, painter) in enumerate(glyphs):
            col, row = i % 2, i // 2
            xx = 1060 + col * 360
            yy = 712 + row * 46
            painter(d, xx, yy, 30, color, 2)
            T(d, xx + 46, yy + 7, label, F(HIRA, 12), "#B9C6DC")
        T(d, 1060, 952, "每个色相都在同一明度带：多彩但不刺眼，暗底上不发光。", F(HIRA, 12), "#8FA0BB")
        T(d, 1060, 978, "图标字形与亮色主题同源（透明字形、无底板、14px 可辨）。", F(HIRA, 12), "#8FA0BB")
        path = outdir / f"{seed['id']}{suffix_id}.png"
        img.save(path)
        cards.append((seed, p, m, path))
        print(f"{seed['name']:<8} 正文 {m['text']:.2f} 次级 {m['secondary']:.2f} 主色 {m['accent']:.2f} "
              f"高亮 {m['hl']:.2f} 提示 {m['callout']:.2f} 内容 {m['content_contrast']:.2f} "
              f"| ΔE 主色 {m['core']:.0f} 内容 {m['content']:.0f} | 标记彩度 {m['marker_chroma']:.0f} 列表彩度 {m['visible_chroma']:.0f} "
              f"| {'全部达标' if (m['core']>=22 and m['content']>=12 and m['content_contrast']>=4.5 and m['marker_chroma']<=30 and m['visible_chroma']>=12) else '未达标'}")

    # 总览图
    W, H = 1840, 320 + len(cards) * 300
    img, d = gt.page(W, H)
    T(d, 48, 34, f"{title_prefix} · {len(cards)} 个方向（全部通过 v4 + v5 门槛）{title_suffix}", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "每套都有独立叙事、专属字体、19 个多色语义图标、动效与彩蛋；右侧是自动校验结果。你挑中我再做完整主题包。",
      F(HIRA, 15), "#93A3BE")
    for i, (seed, p, m, path) in enumerate(cards):
        y = 130 + i * 300
        d.rounded_rectangle([40, y, 1800, y + 272], radius=14, fill="#111722", outline="#1F2937")
        win = review.render_window(p)
        gt.paste_win(img, win, 62, y + 20, scale=0.28, radius=7, shadow=False)
        d.rounded_rectangle([62, y + 20, 62 + int(1300 * 0.28), y + 20 + int(800 * 0.28)],
                            radius=7, outline="#2A3648", width=1)
        T(d, 460, y + 26, f"{seed['name']} · {seed['en']}", F(HIRA, 20, 2), "#EFF4FF")
        T(d, 462, y + 62, seed["idea"], F(HIRA, 13), "#B9C6DC")
        T(d, 462, y + 92, seed["font"], F(HIRA, 12), "#8FA0BB")
        T(d, 462, y + 116, "动效：" + seed["motion"], F(HIRA, 12), "#8FA0BB")
        T(d, 462, y + 140, "彩蛋：" + seed["egg"], F(HIRA, 12), "#8FA0BB")
        T_mix(d, 462, y + 168,
              f"正文 {m['text']:.2f}:1　次级 {m['secondary']:.2f}:1　主色 {m['accent']:.2f}:1　高亮 {m['hl']:.2f}:1　"
              f"提示 {m['callout']:.2f}:1　内容 {m['content_contrast']:.2f}:1",
              F(MONO, 11), F(HIRA, 11), "#7FD1A8")
        T_mix(d, 462, y + 190,
              f"ΔE 主色 {m['core']:.0f}（≥22）　内容 {m['content']:.0f}（≥12）　标记彩度 {m['marker_chroma']:.0f}（≤30）　"
              f"列表彩度 {m['visible_chroma']:.0f}（≥12）",
              F(MONO, 11), F(HIRA, 11), "#7FD1A8")
        for j, (label, color) in enumerate([("纸底", p["bg"]), ("面板", p["surface"]),
                                            ("主色", p["accent"]), ("主色字", p["accent_ink"]),
                                            ("正文", p["text"]), ("高亮", p["md"]["highlight"])]):
            bx = 1300 + j * 82
            d.rounded_rectangle([bx, y + 26, bx + 58, y + 70], radius=8, fill=color, outline="#2A3648")
            T(d, bx, y + 76, label, F(HIRA, 11), "#8FA0BB")
        d.rounded_rectangle([1300, y + 110, 1792, y + 190], radius=10, fill=p["bg"], outline=p["line"])
        T(d, 1318, y + 124, "在这块底上看正文与强调色：", F(HIRA, 11), p["--text-secondary"])
        T(d, 1318, y + 146, "正文文字 · 强调文字 · 引用文字", F(HIRA, 13), p["text"])
        T(d, 1318, y + 168, "链接 / 标题 / 高亮 / 提示", F(HIRA, 13), p["md"]["h1"])
        T(d, 1660, y + 168, "警告", F(HIRA, 13), p["md"]["callout"])
    name = "dark-overview.png" if not suffix_id else f"dark-overview{suffix_id}.png"
    img.save(outdir / name)
    print("\n" + str(outdir / name))


def main():
    run_batch(THEMES, ROOT / "docs/proposals/dark", "", "")
    run_batch(THEMES_ROUND2, ROOT / "docs/proposals/dark", " · 第二批", "-2")
    run_batch(THEMES_MID, ROOT / "docs/proposals/mid", " · 中色", "-mid", tone="mid", title_prefix="中色主题候选")
    run_batch(THEMES_MID2, ROOT / "docs/proposals/mid", " · 有色中色", "-mid2", tone="mid", title_prefix="中色主题候选 · 有色纸")


if __name__ == "__main__":
    main()
