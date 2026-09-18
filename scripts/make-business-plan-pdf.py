#!/usr/bin/env python3
"""生成《随手 MarkNote - 创业计划书》PDF（大学生创业大赛用）。

用法：
    python3 scripts/make-business-plan-pdf.py [输出路径]

依赖：reportlab（Codex 运行时自带）、Pillow（压缩截图）；中文字体取 macOS 自带的
STHeiti（标题）/ Songti（正文）/ Menlo（数字代码）。
"""

import os
import sys
from pathlib import Path

from PIL import Image
from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_JUSTIFY, TA_RIGHT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, CondPageBreak, Flowable, Frame, Image as RLImage,
                                KeepTogether, NextPageTemplate, PageBreak, PageTemplate,
                                Paragraph, Spacer, Table, TableStyle)
from reportlab.platypus.tableofcontents import TableOfContents

ROOT = Path(__file__).resolve().parent.parent
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "output/pdf/随手-创业计划书.pdf"
TMP = ROOT / "tmp/pdfs"
TMP.mkdir(parents=True, exist_ok=True)

# ---------- 字体 ----------
HEITI = "/System/Library/Fonts/STHeiti Light.ttc"
HEITI_M = "/System/Library/Fonts/STHeiti Medium.ttc"
SONGTI = "/System/Library/Fonts/Supplemental/Songti.ttc"
MENLO = "/System/Library/Fonts/Menlo.ttc"

pdfmetrics.registerFont(TTFont("Hei", HEITI, subfontIndex=0))
pdfmetrics.registerFont(TTFont("HeiB", HEITI_M, subfontIndex=0))
pdfmetrics.registerFont(TTFont("Song", SONGTI, subfontIndex=0))
pdfmetrics.registerFont(TTFont("SongB", SONGTI, subfontIndex=1))
pdfmetrics.registerFont(TTFont("Mono", MENLO, subfontIndex=0))
pdfmetrics.registerFont(TTFont("MonoB", MENLO, subfontIndex=1))
pdfmetrics.registerFontFamily("Song", normal="Song", bold="SongB")
pdfmetrics.registerFontFamily("Hei", normal="Hei", bold="HeiB")

# ---------- 配色（和产品「雾青」主题同一系） ----------
TEAL = colors.HexColor("#2E7D72")
TEAL_D = colors.HexColor("#1F5A52")
TEAL_SOFT = colors.HexColor("#E4F0ED")
CINNABAR = colors.HexColor("#C0563C")
INK = colors.HexColor("#1F2328")
GRAY = colors.HexColor("#5C6570")
GRAY_L = colors.HexColor("#8A929C")
PAPER = colors.HexColor("#FBF9F6")
LINE = colors.HexColor("#E3DED6")

PAGE_W, PAGE_H = A4
MARGIN = 18 * mm

# ---------- 样式 ----------
ss = getSampleStyleSheet()
S = {
    "h1": ParagraphStyle("h1", fontName="HeiB", fontSize=17, leading=23, textColor=TEAL_D,
                         spaceBefore=2, spaceAfter=8),
    # 目录标题本身不进目录
    "h1_notoc": ParagraphStyle("h1_notoc", fontName="HeiB", fontSize=17, leading=23, textColor=TEAL_D,
                               spaceBefore=2, spaceAfter=8),
    "h2": ParagraphStyle("h2", fontName="HeiB", fontSize=12.5, leading=18, textColor=INK,
                         spaceBefore=10, spaceAfter=5),
    "h3": ParagraphStyle("h3", fontName="HeiB", fontSize=10.8, leading=15, textColor=TEAL_D,
                         spaceBefore=7, spaceAfter=3),
    "body": ParagraphStyle("body", fontName="Song", fontSize=10.2, leading=16.4, textColor=INK,
                           alignment=TA_JUSTIFY, spaceAfter=5, wordWrap="CJK"),
    "small": ParagraphStyle("small", fontName="Hei", fontSize=8.6, leading=12.6, textColor=GRAY,
                            spaceAfter=3, wordWrap="CJK"),
    "bullet": ParagraphStyle("bullet", fontName="Song", fontSize=10, leading=15.6, textColor=INK,
                             leftIndent=13, firstLineIndent=-13, bulletIndent=2, spaceAfter=2.5,
                             wordWrap="CJK"),
    "cell": ParagraphStyle("cell", fontName="Song", fontSize=9.1, leading=13.4, textColor=INK,
                           wordWrap="CJK"),
    "cellb": ParagraphStyle("cellb", fontName="HeiB", fontSize=9.1, leading=13.4, textColor=INK,
                            wordWrap="CJK"),
    "cellhead": ParagraphStyle("cellhead", fontName="HeiB", fontSize=9.1, leading=13.4,
                               textColor=colors.white, wordWrap="CJK"),
    "caption": ParagraphStyle("caption", fontName="Hei", fontSize=8.4, leading=12, textColor=GRAY_L,
                              alignment=TA_CENTER, spaceBefore=3, spaceAfter=8),
    "toc1": ParagraphStyle("toc1", fontName="HeiB", fontSize=10.2, leading=16.4, textColor=INK),
    "toc2": ParagraphStyle("toc2", fontName="Hei", fontSize=9.3, leading=14, textColor=GRAY,
                           leftIndent=12),
    "cover_title": ParagraphStyle("cover_title", fontName="HeiB", fontSize=34, leading=44,
                                  textColor=colors.white, alignment=TA_CENTER),
    "cover_sub": ParagraphStyle("cover_sub", fontName="Hei", fontSize=13, leading=22,
                                textColor=colors.HexColor("#D8EAE6"), alignment=TA_CENTER),
    "cover_meta": ParagraphStyle("cover_meta", fontName="Hei", fontSize=10, leading=16,
                                 textColor=colors.HexColor("#9FC4BD"), alignment=TA_CENTER),
}


def P(text, style="body"):
    return Paragraph(text, S[style])


def bullets(items, style="bullet", bullet="·"):
    return [Paragraph(f"{bullet}&nbsp;&nbsp;{t}", S[style]) for t in items]


def table(rows, widths, header=True, zebra=True):
    """表格：首行表头（深青底白字），其余斑马纹。"""
    data = []
    for i, row in enumerate(rows):
        line = []
        for j, cell in enumerate(row):
            if isinstance(cell, str):
                st = "cellhead" if (header and i == 0) else ("cellb" if j == 0 and not header else "cell")
                line.append(Paragraph(cell, S[st]))
            else:
                line.append(cell)
        data.append(line)
    t = Table(data, colWidths=widths, repeatRows=1 if header else 0, hAlign="LEFT")
    cmds = [
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 7),
        ("RIGHTPADDING", (0, 0), (-1, -1), 7),
        ("LINEBELOW", (0, 0), (-1, -2), 0.4, LINE),
        ("BOX", (0, 0), (-1, -1), 0.5, LINE),
    ]
    if header:
        cmds += [("BACKGROUND", (0, 0), (-1, 0), TEAL)]
    if zebra:
        start = 1 if header else 0
        for i in range(start, len(data)):
            if (i - start) % 2 == 1:
                cmds.append(("BACKGROUND", (0, i), (-1, i), PAPER))
    t.setStyle(TableStyle(cmds))
    return t


def callout(title, text, color=TEAL_SOFT, bar=TEAL):
    """带左侧色条与底色的说明框（单表两行，底色不会错位）。"""
    t = Table([[Paragraph(f"<b>{title}</b>", S["cellb"])], [Paragraph(text, S["cell"])]],
              colWidths=[PAGE_W - 2 * MARGIN - 6], hAlign="LEFT")
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), color),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 10), ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (0, 0), 8), ("BOTTOMPADDING", (0, 0), (0, 0), 2),
        ("TOPPADDING", (0, 1), (0, 1), 0), ("BOTTOMPADDING", (0, 1), (0, 1), 9),
        ("LINEBEFORE", (0, 0), (0, -1), 3.5, bar),
    ]))
    return KeepTogether([Spacer(1, 3), t, Spacer(1, 6)])


def figure(rel_path, caption, width=None, max_w=478):
    """截图：统一压到 max_w 宽，并转成 JPEG 降低体积。"""
    src = ROOT / rel_path
    im = Image.open(src).convert("RGB")
    if im.width > 1600:
        im = im.resize((1600, int(im.height * 1600 / im.width)), Image.LANCZOS)
    jpg = TMP / (src.stem + ".jpg")
    im.save(jpg, "JPEG", quality=86, optimize=True)
    w = width or max_w
    h = w * im.height / im.width
    max_h = 330
    if h > max_h:
        w = w * max_h / h
        h = max_h
    return KeepTogether([Spacer(1, 2), RLImage(str(jpg), width=w, height=h), P(caption, "caption")])


# ---------- 矢量图（全部用真实数据画，避免把私人笔记截进参赛材料） ----------

THEMES = [
    ("雾青", "#1FA084", "#FAFCF9", "纸感亮色 · 青瓷主色"),
    ("墨纸", "#E24A2B", "#FCF8F0", "宣纸质感 · 朱砂点缀"),
    ("Bubble Pop", "#FF3D9E", "#FFFAFC", "像素糖果风 · 专属像素字体"),
    ("深林夜", "#4FD1A5", "#0E1512", "暗色 · 墨绿森林"),
]


class Diagram(Flowable):
    """按需求画一个固定高度的矢量图（reportlab 原生 canvas）。"""

    def __init__(self, width, height, draw):
        Flowable.__init__(self)
        self.width = width
        self.height = height
        self._draw = draw

    def wrap(self, availWidth, availHeight):
        self.width = min(self.width, availWidth)
        return self.width, self.height

    def draw(self):
        self._draw(self.canv, self.width, self.height)


def arch_diagram():
    """三层结构：写作层 / 资产层 / 扩展层，外加「文件即笔记」底座。"""
    def draw(c, w, h):
        layers = [
            ("写作层", "原生编辑器 · 离线预览管线 · 阅读专注态 · 主题化语法配色", "#E4F0ED", TEAL_D),
            ("资产层", "工作台隔离 · 素材库（引用计数/废纸篓）· 版本快照 · 冲突处理", "#F1F6F4", TEAL_D),
            ("扩展层", "插件市场（4 主题 + 4 视图）· 质量硬门槛 · 采集流水线 · AI 助手", "#FBEFEA", CINNABAR),
        ]
        y = h - 34
        for title, desc, bg, fg in layers:
            c.setFillColor(colors.HexColor(bg))
            c.roundRect(6, y, w - 12, 30, 5, stroke=0, fill=1)
            c.setFillColor(fg)
            c.setFont("HeiB", 10)
            c.drawString(16, y + 11, title)
            c.setFillColor(INK)
            c.setFont("Song", 8.6)
            c.drawString(66, y + 11, desc)
            y -= 38
        # 底座
        c.setFillColor(colors.HexColor("#123D38"))
        c.roundRect(6, y, w - 12, 28, 5, stroke=0, fill=1)
        c.setFillColor(colors.white)
        c.setFont("HeiB", 10)
        c.drawString(16, y + 9, "文件即笔记")
        c.setFont("Song", 8.6)
        c.setFillColor(colors.HexColor("#BFE0DA"))
        c.drawString(86, y + 9, "纯 Markdown / 素材目录可迁移 · 可用任意编辑器打开 · 可放进 Git 与云盘")

    return Diagram(478, 160, draw)


def pipeline_diagram():
    """采集流水线：需求 -> 追问 -> 搜索 -> 候选 -> 入库 -> 报账。"""
    def draw(c, w, h):
        steps = ["一句话需求", "AI 解析成卡", "追问（2-3 轮）", "多源搜索", "候选勾选", "入库 / 报账"]
        bw = (w - 5 * 8) / len(steps)
        y = h - 42
        for i, s in enumerate(steps):
            x = i * (bw + 8)
            c.setFillColor(TEAL if i % 2 == 0 else colors.HexColor("#3E9184"))
            c.roundRect(x, y, bw, 26, 5, stroke=0, fill=1)
            c.setFillColor(colors.white)
            c.setFont("HeiB", 8.8)
            c.drawCentredString(x + bw / 2, y + 9, s)
            if i < len(steps) - 1:
                c.setStrokeColor(GRAY_L)
                c.setLineWidth(0.8)
                c.line(x + bw + 1, y + 13, x + bw + 7, y + 13)
        c.setFillColor(GRAY)
        c.setFont("Song", 8.4)
        c.drawString(2, y - 18, "关键项没确认就继续问：最少 2 轮、最多 3 轮；选项答完也会再确认一轮。")
        c.drawString(2, y - 30, "失败逐条报原因：HTTP 403 防盗链 / 不是图片 / 只有 812 字节 / 没解析出直链。")
        c.drawString(2, y - 42, "命中率工程：防盗链 Referer 三档回退 + 缩略图兜底 + 正文容器启发式提取。")

    return Diagram(478, 120, draw)


PLUGIN_CARDS = [
    ("主题包 × 4", "专属字体 / 语义图标 / 彩蛋 / 动效 · 对比度与体积硬门槛", TEAL),
    ("卡片墙", "按天分组、加星与待办筛选、进度徽章", colors.HexColor("#3E9184")),
    ("素材网格", "缩略图、搜索、未引用筛选、拖拽插入、跨工作台导入", colors.HexColor("#3E9184")),
    ("流程图", "8 种图形、拖拽连线、折线/曲线、自动编号、导出 PNG", colors.HexColor("#3E9184")),
    ("素材采集", "图片 / 视频 / 文章 / 小说 · 站点账号 · AI 追问", CINNABAR),
    ("思维导图（规划）", "复用内置 Mermaid 渲染，避免重复造轮子", colors.HexColor("#B9A06A")),
]


def plugin_grid():
    """插件生态卡片（两列）。"""
    def draw(c, w, h):
        cols, gap = 2, 10
        cw = (w - gap) / cols
        ch = 44
        for i, (title, desc, color) in enumerate(PLUGIN_CARDS):
            col, row = i % cols, i // cols
            x = col * (cw + gap)
            y = h - (row + 1) * (ch + 8)
            c.setFillColor(colors.HexColor("#FBF9F6"))
            c.setStrokeColor(LINE)
            c.setLineWidth(0.5)
            c.roundRect(x, y, cw, ch, 5, stroke=1, fill=1)
            c.setFillColor(color)
            c.rect(x, y, 4, ch, stroke=0, fill=1)
            c.setFillColor(INK)
            c.setFont("HeiB", 9.4)
            c.drawString(x + 12, y + ch - 16, title)
            c.setFillColor(GRAY)
            c.setFont("Song", 8.2)
            c.drawString(x + 12, y + ch - 29, desc[:34])

    return Diagram(478, 3 * 52 + 4, draw)


def theme_swatches():
    """四套主题的色卡（真实色值，来自主题包 CSS）。"""
    def draw(c, w, h):
        cols, gap = 4, 8
        cw = (w - gap * (cols - 1)) / cols
        for i, (name, accent, bg, note) in enumerate(THEMES):
            x = i * (cw + gap)
            # 深色底的色卡用浅色字，否则看不清
            bgc = colors.HexColor(bg)
            dark_card = (bgc.red * 0.299 + bgc.green * 0.587 + bgc.blue * 0.114) < 0.5
            fg_main = colors.white if dark_card else INK
            fg_sub = colors.HexColor("#BFE0DA") if dark_card else GRAY
            c.setFillColor(colors.HexColor(bg))
            c.setStrokeColor(LINE)
            c.roundRect(x, 0, cw, h - 16, 5, stroke=1, fill=1)
            c.setFillColor(colors.HexColor(accent))
            c.roundRect(x + 10, h - 52, cw - 20, 22, 4, stroke=0, fill=1)
            c.setFillColor(fg_main)
            c.setFont("HeiB", 9.6)
            c.drawString(x + 10, h - 70, name)
            c.setFillColor(fg_sub)
            c.setFont("Mono", 7.6)
            c.drawString(x + 10, h - 82, accent.upper())
            c.setFont("Song", 7.8)
            c.drawString(x + 10, h - 94, note[:16])

    return Diagram(478, 112, draw)


def roadmap_timeline():
    """路线图时间轴（已完成 + 3/6/12 个月）。"""
    def draw(c, w, h):
        c.setStrokeColor(TEAL)
        c.setLineWidth(1.4)
        y = h - 34
        c.line(10, y, w - 10, y)
        points = [
            ("已完成", "编辑器 / 预览 / 素材库 / 插件市场 / 4 主题 / 4 插件 / 260+ 测试"),
            ("3 个月", "思维导图（复用 Mermaid）· 站点插件化 · 商店上架准备"),
            ("6 个月", "市场开放提交与自动审核 · 本地大模型 · Windows 验证"),
            ("12 个月", "跨平台 · 团队版 · 插件商业化 · 院校授权"),
        ]
        gap = w / len(points)
        for i, (t, desc) in enumerate(points):
            x = gap * i + gap / 2
            filled = i == 0
            c.setFillColor(TEAL if filled else colors.white)
            c.setStrokeColor(TEAL)
            c.circle(x, y, 4.2, stroke=1, fill=1)
            c.setFillColor(TEAL_D if filled else INK)
            c.setFont("HeiB", 9.4)
            c.drawCentredString(x, y + 12, t)
            c.setFillColor(GRAY)
            c.setFont("Song", 7.9)
            words = desc
            # 手动折行（每行 16 字）
            line = ""
            yy = y - 16
            for ch in words:
                if len(line) >= 16:
                    c.drawCentredString(x, yy, line)
                    line = ""
                    yy -= 10
                line += ch
            if line:
                c.drawCentredString(x, yy, line)

    return Diagram(478, 118, draw)


def revenue_chart():
    """三年收入与成本（柱状，数据来自预测表）。"""
    def draw(c, w, h):
        data = [("Y1", 44320, 17888), ("Y2", 255000, 49088), ("Y3", 1052000, 124688)]
        max_v = max(v for _, v, _ in data)
        base = 22
        bw = 42
        for i, (label, rev, cost) in enumerate(data):
            x = 70 + i * 120
            rh = (h - base - 26) * rev / max_v
            ch_ = (h - base - 26) * cost / max_v
            c.setFillColor(TEAL)
            c.rect(x, base, bw, rh, stroke=0, fill=1)
            c.setFillColor(CINNABAR)
            c.rect(x + bw + 8, base, bw, ch_, stroke=0, fill=1)
            c.setFillColor(GRAY)
            c.setFont("Hei", 7.6)
            c.drawCentredString(x + bw / 2, base + rh + 4, f"{rev/10000:.1f}万")
            c.drawCentredString(x + bw + 8 + bw / 2, base + ch_ + 4, f"{cost/10000:.1f}万")
            c.setFillColor(INK)
            c.setFont("HeiB", 9)
            c.drawCentredString(x + bw + 4, 8, label)
        c.setFillColor(TEAL)
        c.rect(70, h - 10, 10, 7, stroke=0, fill=1)
        c.setFillColor(INK)
        c.setFont("Song", 8)
        c.drawString(84, h - 9, "收入")
        c.setFillColor(CINNABAR)
        c.rect(130, h - 10, 10, 7, stroke=0, fill=1)
        c.setFillColor(INK)
        c.drawString(144, h - 9, "成本")
        c.setFillColor(GRAY_L)
        c.setFont("Song", 7.4)
        c.drawString(230, h - 9, "口径见 5.2 表：买断 98 元 / 年付 128 元 / 席位 298 元 / 市场抽成 30%")

    return Diagram(478, 150, draw)


def clarify_loop_diagram():
    """追问闭环：硬规则优先，选项答完也要再确认一轮。"""
    def draw(c, w, h):
        # 主流程
        nodes = [("一句话需求", 0), ("AI 解析成卡", 1), ("硬规则体检", 2), ("追问一轮", 3), ("需求卡确认", 4)]
        bw, gap = 82, 14
        y = h - 40
        for label, i in nodes:
            x = i * (bw + gap)
            fill = TEAL if i in (0, 4) else colors.HexColor("#3E9184")
            c.setFillColor(fill)
            c.roundRect(x, y, bw, 24, 4, stroke=0, fill=1)
            c.setFillColor(colors.white)
            c.setFont("HeiB", 8.6)
            c.drawCentredString(x + bw / 2, y + 8, label)
            if i < 4:
                c.setStrokeColor(GRAY_L)
                c.line(x + bw + 2, y + 12, x + bw + gap - 2, y + 12)
        # 回环箭头：追问 -> 再审
        c.setStrokeColor(CINNABAR)
        c.setLineWidth(1.1)
        x3 = 3 * (bw + gap) + bw / 2
        x2 = 2 * (bw + gap) + bw / 2
        c.line(x3, y - 2, x3, y - 16)
        c.line(x3, y - 16, x2, y - 16)
        c.line(x2, y - 16, x2, y - 2)
        c.setFillColor(CINNABAR)
        c.setFont("Song", 7.8)
        c.drawCentredString((x2 + x3) / 2, y - 26, "答完再体检：关键项没齐就继续问（最少 2 轮 / 最多 3 轮）")
        # 规则清单
        c.setFillColor(INK)
        c.setFont("HeiB", 8.8)
        c.drawString(2, y - 48, "硬规则（模型说「懂了」也要过）：")
        c.setFillColor(GRAY)
        c.setFont("Song", 8.2)
        c.drawString(2, y - 60, "· 关键项：类型与主题、图片的用途/方向、视频的时长/平台、文章的体裁、小说的章节范围")
        c.drawString(2, y - 71, "· 能安全默认的（数量、语言、是否合并文件）不问；用户选「没有了，就这样」立刻停止追问")

    return Diagram(478, 132, draw)


def stat_row(items):
    """一排数字卡片（关键指标）。"""
    cells = []
    for value, label in items:
        cells.append(Table([[Paragraph(f'<font name="HeiB" size="17" color="#1F5A52">{value}</font>',
                                      S["cell"])],
                            [Paragraph(label, S["small"])]],
                           colWidths=[(PAGE_W - 2 * MARGIN - 8 * (len(items) - 1)) / len(items)]))
    for c in cells:
        c.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), TEAL_SOFT),
            ("BOX", (0, 0), (-1, -1), 0.4, colors.HexColor("#C9DFDA")),
            ("ALIGN", (0, 0), (-1, 0), "CENTER"),
            ("TOPPADDING", (0, 0), (-1, 0), 8),
            ("BOTTOMPADDING", (0, 1), (-1, 1), 8),
            ("LEFTPADDING", (0, 0), (-1, -1), 4), ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ]))
    row = Table([cells], colWidths=[(PAGE_W - 2 * MARGIN - 8 * (len(items) - 1)) / len(items) + 8] * len(items))
    row.setStyle(TableStyle([("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (0, 0), 8),
                             ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0)]))
    return KeepTogether([Spacer(1, 4), row, Spacer(1, 8)])


def figure_pair(left, left_caption, right, right_caption, heights=250):
    """两张图并排（附录用），避免各自占一整页、留下大片空白。"""
    imgs = []
    for rel in (left, right):
        src = ROOT / rel
        im = Image.open(src).convert("RGB")
        if im.width > 1400:
            im = im.resize((1400, int(im.height * 1400 / im.width)), Image.LANCZOS)
        jpg = TMP / (src.stem + "-pair.jpg")
        im.save(jpg, "JPEG", quality=86, optimize=True)
        w = heights * im.width / im.height
        imgs.append(RLImage(str(jpg), width=w, height=heights))
    t = Table([[imgs[0], imgs[1]],
               [Paragraph(left_caption, S["caption"]), Paragraph(right_caption, S["caption"])]],
              colWidths=[(PAGE_W - 2 * MARGIN) / 2] * 2, hAlign="LEFT")
    t.setStyle(TableStyle([
        ("ALIGN", (0, 0), (-1, -1), "CENTER"),
        ("VALIGN", (0, 0), (-1, 0), "MIDDLE"),
        ("TOPPADDING", (0, 1), (-1, 1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return KeepTogether([Spacer(1, 4), t, Spacer(1, 8)])


class PlanDoc(BaseDocTemplate):
    """带页眉页脚 + 目录的文档模板。"""

    def __init__(self, filename, **kw):
        super().__init__(filename, pagesize=A4,
                         leftMargin=MARGIN, rightMargin=MARGIN,
                         topMargin=MARGIN + 4 * mm, bottomMargin=MARGIN,
                         title="随手 MarkNote - 创业计划书", author="随手 MarkNote",
                         subject="大学生创业大赛项目计划书", **kw)
        frame = Frame(MARGIN, MARGIN, PAGE_W - 2 * MARGIN, PAGE_H - 2 * MARGIN - 6 * mm, id="body")
        self.addPageTemplates([
            PageTemplate(id="cover", frames=[frame], onPage=self.cover_page),
            PageTemplate(id="body", frames=[frame], onPage=self.header_footer),
        ])

    def cover_page(self, canvas, doc):
        canvas.saveState()
        canvas.setFillColor(colors.HexColor("#123D38"))
        canvas.rect(0, 0, PAGE_W, PAGE_H, stroke=0, fill=1)
        # 装饰：右上角圆弧与网格点
        canvas.setFillColor(colors.HexColor("#17504A"))
        canvas.circle(PAGE_W + 20 * mm, PAGE_H - 30 * mm, 70 * mm, stroke=0, fill=1)
        canvas.setFillColor(colors.HexColor("#1B5C55"))
        canvas.circle(-10 * mm, 20 * mm, 45 * mm, stroke=0, fill=1)
        canvas.setFillColor(colors.HexColor("#2E7D72"))
        step = 7 * mm
        y = PAGE_H - 150 * mm
        while y < PAGE_H - 60 * mm:
            x = MARGIN
            while x < MARGIN + 60 * mm:
                canvas.circle(x, y, 0.7, stroke=0, fill=1)
                x += step
            y += step
        canvas.restoreState()

    def header_footer(self, canvas, doc):
        canvas.saveState()
        canvas.setStrokeColor(LINE)
        canvas.setLineWidth(0.5)
        canvas.line(MARGIN, PAGE_H - MARGIN - 2 * mm, PAGE_W - MARGIN, PAGE_H - MARGIN - 2 * mm)
        canvas.setFont("Hei", 7.8)
        canvas.setFillColor(GRAY_L)
        canvas.drawString(MARGIN, PAGE_H - MARGIN + 1.6 * mm, "随手 MarkNote · 大学生创业大赛项目计划书")
        canvas.drawRightString(PAGE_W - MARGIN, PAGE_H - MARGIN + 1.6 * mm, "本地优先的 Markdown 知识工作台")
        canvas.line(MARGIN, MARGIN - 4 * mm, PAGE_W - MARGIN, MARGIN - 4 * mm)
        canvas.drawCentredString(PAGE_W / 2, MARGIN - 9 * mm, f"- {doc.page} -")
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            style = flowable.style.name
            if style in ("h1", "h2"):
                level = 0 if style == "h1" else 1
                text = flowable.getPlainText()
                self.notify("TOCEntry", (level, text, self.page))


# ============================== 正文内容 ==============================

def build_story():
    story = []

    # ---------- 封面 ----------
    story += [Spacer(1, 30 * mm)]
    story.append(P("随手 MarkNote", "cover_title"))
    story.append(Spacer(1, 4 * mm))
    story.append(P("本地优先的 Markdown 知识工作台", "cover_sub"))
    story.append(P("文件即笔记 · 主题化体验 · 插件化扩展 · AI 可选", "cover_meta"))
    story.append(Spacer(1, 14 * mm))
    story.append(stat_row([("27.5k", "行 Swift 源码"), ("260+", "项自动化测试"),
                           ("4 套", "审核制主题"), ("9 个", "插件包")]))
    story.append(Spacer(1, 12 * mm))
    story.append(P("大学生创业大赛 · 项目计划书", "cover_sub"))
    story.append(Spacer(1, 34 * mm))
    story.append(P("项目类型：个人开发者软件产品（macOS 桌面端）", "cover_meta"))
    story.append(P("参赛赛道：软件与信息技术服务 / 数字内容与工具", "cover_meta"))
    story.append(P("开源地址：github.com/yunsu-coder/suishou", "cover_meta"))
    story.append(Spacer(1, 6 * mm))
    story.append(P("说明：本计划书中的产品能力、测试数据、实测结论均来自当前可运行版本；"
                   "市场与财务部分为量级估算与预测，已标注口径。", "cover_meta"))
    story.append(NextPageTemplate("body"))
    story.append(PageBreak())

    # ---------- 目录 ----------
    story.append(P("目录", "h1_notoc"))
    toc = TableOfContents()
    toc.levelStyles = [S["toc1"], S["toc2"]]
    story.append(toc)
    story.append(PageBreak())

    # ---------- 一、项目概述 ----------
    story.append(P("一、项目概述", "h1"))
    story.append(P(
        "「随手」是一款运行在 macOS 上的 Markdown 笔记与素材工作台。它把三件容易被割裂的事情放在一起："
        "<b>写</b>（原生编辑器与所见即所得预览）、<b>存</b>（文件即笔记、素材自动入库）、"
        "<b>找</b>（插件化的卡片墙、素材网格与素材采集）。所有内容都是普通文件，"
        "用户可以随时用别的编辑器打开、备份或放进 Git 仓库。", "body"))
    story.append(P("1.1 用户痛点", "h2"))
    story += bullets([
        "<b>工具割裂</b>：写作、剪藏、素材管理分散在三四个软件里，素材靠手动命名与手动搬运。",
        "<b>格式私有</b>：云笔记把内容锁在数据库里，导出后结构丢失，迁移成本高。",
        "<b>主题与插件生态质量参差</b>：换肤只换颜色、插件破坏排版，长时间使用体验下降。",
        "<b>AI 要么不可用，要么不可控</b>：内置模型不可替换、隐私不透明、按次收费。",
    ])
    story.append(P("1.2 产品定位与愿景", "h2"))
    story.append(P(
        "定位：<b>给中文知识工作者的本地优先知识工作台</b>。第一版聚焦 macOS（中文用户中创作者与开发者密度高、"
        "系统级体验可控），用「主题质量门槛 + 声明式插件」建立差异化体验，用「文件即笔记」建立信任。"
        "愿景：让本地文件成为知识资产的标准容器，让插件生态在<b>质量可控</b>的前提下生长。", "body"))
    story.append(callout("一页速览（当前版本已具备）",
                         "原生编辑器（33 类语法高亮，预览与编辑共用主题配色）· 离线预览管线"
                         "（markdown-it / KaTeX / Mermaid / highlight.js）· 工作台隔离与素材库（引用计数、"
                         "废纸篓、跨工作台导入）· 插件市场（4 套审核制主题 + 4 个视图插件）· "
                         "素材采集（图片 / 视频 / 文章 / 小说四类，18 个站点账号）· 流程图插件 · "
                         "AI 助手（用户自备 API Key，需求追问闭环）。"))
    story.append(PageBreak())

    # ---------- 二、产品与核心能力 ----------
    story.append(P("二、产品与核心能力", "h1"))
    story.append(arch_diagram())
    story.append(P("图 1　产品结构：写作 / 资产 / 扩展三层，全部落在「文件即笔记」的底座上", "caption"))
    story.append(P("2.1 写作与阅读", "h2"))
    story += bullets([
        "原生 NSTextView 编辑器：行号、当前行高亮、括号匹配、33 类 Markdown 语法高亮（含多级编号 1.1.1）。",
        "离线预览管线：单 WKWebView 渲染 markdown-it / KaTeX / Mermaid / highlight.js，无网络也完整可用。",
        "阅读专注态（Cmd+Shift+R）：隐藏侧栏与工具栏，全宽沉浸；Esc 或开始打字退出。",
        "编辑器与预览共用当前主题的同一套语法配色，消除「拼接缝」。",
    ])
    story.append(P("2.2 素材库与工作台隔离", "h2"))
    story.append(P(
        "工作台就是一个文件夹：笔记是 .md，素材按类型自动归入 source/（图片 / 视频 / 音频 / 文档），"
        "拖入或粘贴即入库，命名统一为「日期-描述」。素材面板支持搜索、未引用筛选、引用计数与废纸篓删除；"
        "跨工作台导入采用<b>勾选式复制</b>，原工作台只读，避免误删与串数据。", "body"))
    story.append(plugin_grid())
    story.append(P("图 2　插件生态：主题包与四个视图插件（思维导图为 3 个月内的规划项）", "caption"))
    story.append(P("2.3 主题体系与质量硬门槛", "h2"))
    story.append(P(
        "主题不是「换皮」：每个主题包必须带专属字体、语义图标、彩蛋与动效，并通过对比度与体积门槛，"
        "否则在扫描阶段就不进列表。当前四套主题覆盖亮色与暗色：", "body"))
    story.append(table([
        ["主题", "风格定位", "专属内容"],
        ["雾青", "纸感亮色 + 青瓷主色", "植物语义图标、开花彩蛋、花粉尘动效"],
        ["墨纸", "宣纸质感 + 朱砂点缀", "朱砂强调色、书法感标题、晕染动效"],
        ["Bubble Pop", "像素糖果风（亮色）", "像素字体、彩色像素图标、弹跳交互"],
        ["深林夜", "暗色 · 墨绿森林", "夜林配色、萤火氛围、暗色专用对比度校准"],
    ], widths=[60, 150, 258]))
    story.append(Spacer(1, 6))
    story.append(theme_swatches())
    story.append(P("图 3　四套主题的真实主色与底色（取自主题包 CSS，非示意图）", "caption"))
    story.append(figure("docs/screenshots/theme-progress-bar.png",
                        "图 4　同一组件在四套主题下的真实渲染（采集进度条）：颜色、字体、动效全部跟随主题",
                        max_w=430))
    story.append(PageBreak())

    story.append(P("2.4 插件市场：声明式、可审核", "h2"))
    story.append(P(
        "插件只声明配置（manifest + 数据文件），不执行任意用户代码，因此可以做到「安装即用、卸载即净」。"
        "市场当前只保留两类：主题包与视图插件（卡片墙、素材网格、流程图、素材采集）。"
        "所有插件界面必须使用主题变量（禁止硬编码色值与字体），提交时附四主题对照图。", "body"))
    story.append(P("2.5 素材采集：把「找素材」变成一条流水线", "h2"))
    story += bullets([
        "<b>四类目标</b>：图片、视频、文章、小说，其中文章与小说直接转成 Markdown 笔记写进工作台。",
        "<b>需求卡片 30+ 选项</b>：风格、画面、来源、时效、授权、入库策略等；AI 解析后自动填卡。",
        "<b>AI 追问闭环</b>：关键项没确认就继续追问（最少 2 轮、最多 3 轮），选完选项也会再确认一轮。",
        "<b>失败必须报账</b>：逐条列出「HTTP 403 防盗链 / 不是图片 / 只有 812 字节」等原因，不再静默少几个。",
        "<b>站点账号</b>：18 个站点应用内登录（cookie 只存本机、只在该站域名使用），登录后原图 / 长文 / 1080P 可达。",
        "<b>抓取工程</b>：防盗链 Referer 三档回退 + 缩略图兜底 + 正文提取（容器启发式）与小说章节拼装。",
    ])
    story.append(pipeline_diagram())
    story.append(P("图 5　采集流水线：需求到入库的六个环节，以及每一步的容错设计", "caption"))
    story.append(clarify_loop_diagram())
    story.append(P("图 6　AI 追问闭环：硬规则优先于模型判断，选项答完仍会再确认一轮", "caption"))
    story.append(PageBreak())

    # ---------- 三、技术与壁垒 ----------
    story.append(P("三、技术架构与竞争壁垒", "h1"))
    story.append(P("3.1 架构总览", "h2"))
    story.append(table([
        ["层", "方案", "说明"],
        ["界面", "SwiftUI + AppKit（NSViewRepresentable）", "原生控件性能；主题变量驱动全局外观"],
        ["编辑", "NSTextView + 自研高亮/行号", "33 类语法高亮；大文档输入无卡顿（有性能测试）"],
        ["预览", "WKWebView + 离线管线", "markdown-it / KaTeX / Mermaid / highlight.js 全部本地打包"],
        ["数据", "文件直写（atomic）+ 外部变更监听", "冲突检测与处理；保存前自动版本快照（10 份）"],
        ["插件", "声明式包（manifest + 数据文件）", "不执行任意代码；质量门槛 + 人工审核"],
        ["AI", "用户自备 Key（DeepSeek 流式 SSE）", "工具调用式文件代理、@文件引用、对话历史落盘"],
    ], widths=[52, 176, 240]))
    story.append(P("3.2 壁垒来自哪", "h2"))
    story += bullets([
        "<b>体验护城河</b>：主题质量硬门槛 + 编辑器与预览共用配色 + 进度条/失败提示等细节统一由主题驱动，"
        "同类工具通常是「换色即主题」。",
        "<b>工程护城河</b>：260+ 项自动化测试（含渲染回归、性能、主题审计），单人也能持续迭代而不崩坏。",
        "<b>数据护城河</b>：文件即笔记，用户资产可迁移；因此口碑来自「可信」，不是靠锁定。",
        "<b>合规护城河</b>：不内置站点签名逆向（避免触碰站点保护措施），采集只做公开可取的抓取 + 用户主动登录，"
        "cookie 只存本机。",
    ])
    story.append(callout("数据驱动的工程习惯（可复验）",
                         "采集能力的每次调整都先做对照实测：例如「登录对公开文章是否真的更全」实测结论是"
                         "掘金 7071 → 7071 字、少数派 2545 → 2545 字（无差别），因此把优化重点从「登录」"
                         "转向「失败可见 + 防盗链回退 + 正文提取」，避免把资源花在伪需求上。",
                         color=colors.HexColor("#FBEFEA"), bar=CINNABAR))
    story.append(PageBreak())

    # ---------- 四、市场分析 ----------
    story.append(P("四、市场分析", "h1"))
    story.append(P("4.1 目标用户", "h2"))
    story.append(table([
        ["人群", "规模量级（估算）", "核心诉求", "付费意愿"],
        ["大学生 / 研究生", "在校 4000 万+，其中重度笔记用户约 5%", "课程笔记、论文素材、答辩材料", "低客单价、愿买断"],
        ["开发者 / 产品经理", "中国 macOS 开发者数百万量级", "技术文档、方案与流程图、素材归档", "中高，愿订阅"],
        ["创作者 / 写作者", "自媒体与自由职业者千万量级", "长文写作、配图管理、导出发布", "中，愿买断"],
        ["高校 / 小型团队", "院系与 10-50 人团队", "本地合规、批量授权、素材共享", "高，按席授权"],
    ], widths=[92, 138, 156, 82]))
    story.append(P(
        "口径说明：以上为公开资料量级估算（中国 PC 年出货约 4000 万台，macOS 占比约一成，"
        "存量设备数千万台），仅用于判断市场量级与优先级，不作为收入测算的唯一依据。", "small"))
    story.append(P("4.2 竞品对比", "h2"))
    story.append(table([
        ["产品", "类型", "优势", "缺口（我们的机会）"],
        ["Obsidian", "本地 Markdown", "插件生态强、社区大", "中文主题与素材/采集链路弱；插件质量参差"],
        ["Notion / 语雀", "云文档", "协作与模板丰富", "非本地文件、离线与隐私顾虑、国内访问体验不稳"],
        ["Typora", "单文档编辑器", "写作体验好", "无工作台、无素材库、无插件体系"],
        ["思源笔记", "本地块级", "本地 + 双链活跃", "资产管理与采集能力有限；主题门槛较低"],
        ["系统备忘录 / Bear", "轻量笔记", "上手快", "Markdown 与扩展能力弱；无法承载素材工作流"],
        ["随手（本项目）", "本地 Markdown 工作台", "文件即笔记 + 主题质量门槛 + 声明式插件 + 采集流水线", "生态尚早期，需持续补充主题与插件供给"],
    ], widths=[70, 96, 126, 176]))
    story.append(P("4.3 差异化定位", "h2"))
    story += bullets([
        "<b>对个人用户</b>：5 分钟内把已有 Markdown 文件夹变成「笔记 + 素材 + 插件」的工作台，"
        "不需要导入导出，也不用担心格式被锁。",
        "<b>对设计 / 内容专业</b>：主题不是换色而是成套设计（字体、图标、彩蛋、动效、对比度），"
        "写作界面本身就是作品的一部分。",
        "<b>对高校与团队</b>：本地文件满足数据合规，批量授权与素材共享可按院系落地，"
        "采集链路能直接服务论文、答辩与课程材料准备。",
    ])
    story.append(PageBreak())

    # ---------- 五、商业模式 ----------
    story.append(P("五、商业模式", "h1"))
    story.append(P(
        "采取「<b>开源核心 + 增值授权 + 插件市场分成</b>」的组合：核心编辑与本地能力开源免费，"
        "降低获客成本并建立信任；增值来自专业版授权、插件市场与服务，收入与生态同步增长。", "body"))
    story.append(table([
        ["收入线", "内容", "定价（建议）", "说明"],
        ["专业版买断", "进阶插件（思维导图等）、批量导出、团队素材共享", "98 元 / 台", "一次性，学生优惠 48 元"],
        ["订阅", "持续更新的主题与插件合集、优先支持", "18 元 / 月，128 元 / 年", "年付折算约 6 折"],
        ["插件市场分成", "第三方主题 / 插件付费销售", "平台抽成 30%", "作者 70%，鼓励生态供给"],
        ["校园 / 企业授权", "院系实验室、团队工作台批量授权", "298 元 / 席 / 年", "含部署与素材库规范咨询"],
        ["定制服务", "主题定制（品牌色 / 专属图标 / 字体）", "项目制 5,000 元 起", "面向高校与中小企业品牌素材库"],
    ], widths=[82, 176, 108, 102]))
    story.append(P("5.1 成本结构（年）", "h2"))
    story.append(table([
        ["科目", "Y1（元）", "Y2（元）", "Y3（元）", "备注"],
        ["开发设备与测试机", "8,000", "6,000", "8,000", "覆盖新系统适配与多机型验证"],
        ["Apple 开发者账号", "688", "688", "688", "上架与公证"],
        ["域名 / 静态托管 / CDN", "1,200", "2,400", "6,000", "官网、插件市场索引、更新分发"],
        ["设计与外包", "6,000", "12,000", "30,000", "主题视觉、图标、宣传物料"],
        ["市场与校园推广", "2,000", "20,000", "60,000", "校园大使、赛事与内容投放"],
        ["法务与财务", "0", "8,000", "20,000", "授权协议、发票与合规"],
        ["合计", "17,888", "49,088", "124,688", ""],
    ], widths=[108, 62, 62, 62, 176]))
    story.append(P("5.2 三年收入预测（保守）", "h2"))
    story.append(KeepTogether([table([
        ["指标", "Y1", "Y2", "Y3"],
        ["专业版买断（份）", "300", "1,500", "5,000"],
        ["订阅（年付份数）", "80", "600", "2,400"],
        ["校园 / 企业席位", "10", "120", "600"],
        ["插件市场 GMV（抽成前，元）", "10,000", "80,000", "400,000"],
        ["收入合计（元）", "44,320", "255,000", "1,052,000"],
        ["成本合计（元）", "17,888", "49,088", "124,688"],
        ["净收益（税前，元）", "26,432", "205,912", "927,312"],
    ], widths=[150, 100, 100, 118]),
        Spacer(1, 4),
        P("测算口径：买断 98 元、年付 128 元、席位 298 元/年、市场抽成 30%。Y1 假设仅通过校园与开源社区自然增长，"
          "不含任何付费投放；若获得赛事奖金或学校孵化支持，将优先投入主题与插件作者激励。", "small")]))
    story.append(revenue_chart())
    story.append(P("图 7　三年收入与成本（万元）", "caption"))
    story.append(PageBreak())

    # ---------- 六、营销与增长 ----------
    story.append(P("六、营销与增长策略", "h1"))
    story.append(P("6.1 三条获客渠道", "h2"))
    story += bullets([
        "<b>开源与社区</b>：GitHub 公开仓库 + README 双语；以「可复验的工程细节」（测试数、实测对照、"
        "质量门槛）作为内容素材，在少数派、掘金、V2EX、B 站做技术长文与录屏。",
        "<b>校园渠道</b>：与本校计算机 / 设计 / 新闻传播院系合作，做「论文与答辩素材工作流」工作坊；"
        "招募校园大使（返佣 + 免费授权），覆盖 20 所高校做种子用户。",
        "<b>主题与插件比赛</b>：面向设计专业学生办主题创作赛（像素 / 水墨 / 赛博），"
        "获奖作品进市场并分成，既补内容供给又带传播。",
    ])
    story.append(P("6.2 增长节奏（首年）", "h2"))
    story.append(table([
        ["阶段", "时间", "动作", "目标"],
        ["冷启动", "第 1-2 月", "开源发布 + 3 篇技术长文 + 2 支演示视频", "GitHub 关注 300+"],
        ["校园试点", "第 3-5 月", "5 所高校工作坊，收集 50 份深度反馈", "种子用户 500+"],
        ["生态启动", "第 6-8 月", "主题创作赛 + 插件提交规范公开", "第三方插件 10+"],
        ["商业化", "第 9-12 月", "专业版上线，学生优惠 + 校园大使返佣", "付费用户 300+"],
    ], widths=[62, 62, 226, 118]))
    story.append(P("6.3 留存与口碑", "h2"))
    story += bullets([
        "「零迁移成本」是最大卖点：首次启动即可指向已有 Markdown 文件夹，5 分钟看到价值。",
        "把「失败必须说清楚」的产品习惯延续到售后：每个问题给复现命令与原因，不糊弄。",
        "公开路线图与更新日志（CHANGELOG），让用户看到迭代速度。",
    ])
    story.append(PageBreak())

    # ---------- 七、团队 ----------
    story.append(P("七、团队与分工", "h1"))
    story.append(P(
        "当前为<b>个人开发者 + AI 协作</b>的精益形态：产品定义、架构、开发、测试、主题设计均由本人完成，"
        "借助 AI 编程与自建测试体系把单人产出拉到小团队水平（27.5k 行源码、260+ 测试、76 次提交、"
        "从零到完整插件市场约半年）。", "body"))
    story.append(table([
        ["角色", "现状", "计划"],
        ["产品 / 架构 / 开发", "本人（全职投入）", "Y1 内保持单人主开发，关键模块外包设计"],
        ["设计与主题", "本人（已产出 4 套主题）", "招募 1 名视觉设计（兼职 / 校园合作）"],
        ["市场与运营", "暂无", "Y1 Q2 起招募 1 名运营（负责校园大使与内容）"],
        ["测试与质量", "自建自动化（260+ 项）", "随插件生态开放，引入社区测试者"],
        ["顾问", "暂无", "邀请 1 名高校导师 + 1 名创业导师"],
    ], widths=[110, 180, 178]))
    story.append(callout("为什么单人 + AI 也能做成",
                         "本项目把「可验证」当作第一原则：所有关键行为都有自动化测试与渲染检查，"
                         "主题与插件有可执行的质量门槛（域名撞车、对比度、体积等），"
                         "因此迭代速度快但不容易崩坏；这也是小团队对抗大厂生态的现实路径。"))
    story.append(PageBreak())

    # ---------- 八、里程碑 ----------
    story.append(P("八、里程碑与路线图", "h1"))
    story.append(roadmap_timeline())
    story.append(P("图 8　路线图：已完成与 3 / 6 / 12 个月计划", "caption"))
    story.append(table([
        ["阶段", "状态", "内容"],
        ["已完成", "已交付", "原生编辑器与预览管线、素材库与工作台隔离、版本快照与冲突处理、"
                         "插件市场与质量门槛、4 套主题、卡片墙 / 素材网格 / 流程图 / 素材采集四个视图插件、"
                         "AI 助手与需求追问闭环、260+ 项自动化测试"],
        ["3 个月", "计划", "思维导图插件（复用内置 Mermaid 渲染，避免重复造轮子）、"
                          "采集的站点插件化（把站点专用能力放进可选插件包）、上架 Mac App Store 准备"],
        ["6 个月", "计划", "插件市场开放第三方提交与自动审核（质量门槛可执行化）、"
                          "本地大模型接入（Ollama / MLX，完全离线）、Windows 版可行性验证"],
        ["12 个月", "计划", "跨平台（Windows / iPad）、团队版（加密同步与素材共享）、"
                           "插件市场商业化与作者激励计划、院校批量授权"],
    ], widths=[58, 46, 364]))
    story.append(P("8.1 产品原则（长期不变）", "h2"))
    story += bullets([
        "文件即笔记：任何功能都不能以「锁住用户数据」为代价。",
        "质量优先于数量：主题与插件宁缺毋滥，门槛可执行、可复验。",
        "AI 可选、可控、可替换：API Key 与模型由用户决定；不起作用的能力不写进宣传。",
        "诚实报错：做不到就说清楚为什么，不静默失败。",
    ])
    story.append(PageBreak())

    # ---------- 九、风险 ----------
    story.append(P("九、风险与应对", "h1"))
    story.append(table([
        ["风险", "影响", "应对"],
        ["平台依赖（macOS / App Store 政策）", "上架审核与分发受限", "开源分发（官网 + GitHub）与商店并行；"
                                                                    "核心能力不依赖私有 API；提前按审核指南整改"],
        ["竞品生态（Obsidian 等）", "获客成本高", "差异化在中文主题质量与素材采集流水线；"
                                                 "以「文件即可迁移」降低用户迁移顾虑"],
        ["单人团队与精力上限", "迭代速度受限", "自动化测试 + 质量门槛把回归成本压低；"
                                               "关键路径外包（设计 / 运营），Y1 内引入 1-2 名伙伴"],
        ["采集合规与站点反爬", "法律与稳定性风险", "不内置站点签名逆向；只抓公开可取内容 + 用户主动登录；"
                                                    "cookie 只存本机；被拒站点如实报错并提示登录"],
        ["AI 成本与服务可用性", "体验波动", "用户自备 Key；本地模型预案（Ollama / MLX）；"
                                              "AI 失败时全流程可手工完成"],
        ["主题 / 插件质量失控", "品牌受损", "硬门槛 + 人工审核 + 四主题对照图；"
                                            "市场只保留审核通过的包"],
    ], widths=[118, 108, 242]))
    story.append(PageBreak())

    # ---------- 附录 ----------
    story.append(P("附录 A：界面与细节（产品自渲染图）", "h1"))
    story.append(P(
        "以下图由产品自身的渲染管线生成（非截图），因此不含任何个人内容；"
        "完整界面演示可通过安装包或演示视频查看。", "small"))
    story.append(figure_pair("docs/screenshots/collector-accounts.png",
                             "图 A1　站点账号面板（产品自渲染）",
                             "docs/screenshots/theme-progress-bar.png",
                             "图 A2　四套主题下的进度条渲染",
                             heights=250))
    story.append(PageBreak())
    story.append(P("附录 B：质量与验证数据", "h1"))
    story.append(table([
        ["指标", "数值", "说明"],
        ["源码规模", "27,463 行 Swift", "Sources/MarkNote（不含测试）"],
        ["自动化测试", "6,344 行 / 260+ 项", "含渲染回归、性能、主题审计、插件质量门槛"],
        ["插件包", "9 个", "4 主题 + 4 视图插件 + 1 评审目录"],
        ["提交记录", "76 次", "全部为可运行的增量提交（含测试）"],
        ["平台要求", "macOS 14+", "Swift Package Manager；原生 SwiftUI + AppKit"],
        ["开源许可", "见仓库 LICENSE", "github.com/yunsu-coder/suishou"],
    ], widths=[86, 128, 254]))
    story.append(Spacer(1, 6))
    story.append(P(
        "联系方式与后续材料：可提供可运行安装包、演示视频、测试报告与主题对照图；"
        "如需现场演示，可在评委机（macOS 14+）上 3 分钟内完成安装与首篇笔记。", "small"))
    return story


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = PlanDoc(str(OUT))
    doc.multiBuild(build_story())
    print("PDF 已生成：", OUT)
    size = OUT.stat().st_size / 1024 / 1024
    print(f"体积：{size:.2f} MB（上限 20 MB）")


if __name__ == "__main__":
    main()
