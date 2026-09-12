#!/usr/bin/env python3
"""插件包方向提案图 · 第二批：按「资产 / 陪伴 / 搬运」三类重新想。

用法: python3 scripts/make-plugin-directions2.py [输出.png]
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
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO

FAMILIES = [
    dict(
        key="A", title="资产 · 把笔记变成拿得出手的东西", accent="#7FD1C0",
        note="这一类直接解决「我写它干嘛」——写完能分享、能发布、能看全貌，是最容易让人想装的。",
        items=[
            dict(name="分享卡片", star=3, want="一键把笔记做成方图/长图卡片，直接发朋友圈、小红书",
                 how="卡片模板（主题色 + 主题字体 + 留白规则）+ 导出 PNG/长图",
                 app="需要 app 加「渲染成交付图」的能力（WKWebView 截图，本地完成）", cost="低中"),
            dict(name="发布 / 电子书", star=3, want="把一批笔记变成能给人看的成品：静态网页或 EPUB/PDF 小册",
                 how="站点/书籍模板 + 目录编排 + 主题样式绑定",
                 app="需要 app 加多文档合并导出（现在只导单篇）", cost="中"),
            dict(name="双链与图谱", star=2, want="看笔记之间的关联：谁引用了我、我在哪提过它",
                 how="[[双链]] 语法 + 反链面板 + 图谱布局参数",
                 app="需要 app 加索引与图谱视图", cost="高"),
            dict(name="每日回顾", star=2, want="自动生成日报/周报，还能翻出「三年前的今天」",
                 how="回顾模板 + 时间规则 + 折叠样式",
                 app="需要 app 加定时生成与检索", cost="中"),
        ]),
    dict(
        key="B", title="陪伴 · 让「写」这件事有情绪", accent="#E8A0C0",
        note="这一类不提高效率，但让人愿意打开软件——你现在装了深林夜，就是为这个买单。",
        items=[
            dict(name="桌面宠物", star=3, want="写作时旁边有只小生灵，写得越多它越活泼",
                 how="宠物包（精灵图 + 动画 + 互动动作 + 成长规则）",
                 app="需要 app 加宠物层（透明浮层 + 状态持久化）", cost="中"),
            dict(name="写作音效", star=3, want="机械键盘声、雨声、咖啡馆底噪——戴上耳机就进状态",
                 how="音效包（本地音频 + 触发规则 + 音量曲线）",
                 app="需要 app 加音频播放（本地文件，不联网）", cost="低中"),
            dict(name="专注陪伴", star=2, want="番茄钟 + 专注计时的陪伴感，结束时给一个仪式",
                 how="计时规则 + 结束动作（收尾音效/落款）",
                 app="需要 app 加计时器与状态栏指示", cost="低中"),
            dict(name="仪式彩蛋", star=2, want="写完一篇→落款印章 / 写完一天→点亮灯",
                 how="触发规则 + 视觉后果（与主题彩蛋同一机制）",
                 app="几乎不用改（复用主题彩蛋通道）", cost="低"),
        ]),
    dict(
        key="C", title="搬运 · 把外面的东西带进来", accent="#8FB8FF",
        note="这一类降低「开始写」的门槛——很多笔记死在「先复制粘贴再清理格式」这一步。",
        items=[
            dict(name="剪藏收件箱", star=3, want="粘一段网页/公众号文章 → 自动变成干净 Markdown 入库",
                 how="清洗规则（去广告/去样式/留来源）+ 收件箱目录约定",
                 app="需要 app 加 HTML→Markdown 清洗（本地可做）", cost="中"),
            dict(name="语音转写", star=2, want="说话变文字，边走边记",
                 how="转写配置 + 分段规则 + 时间戳格式",
                 app="需要 app 接系统语音识别（本地优先）", cost="中高"),
            dict(name="截图 / 图片工具", star=2, want="截图直接入库、粘贴的图自动存 source/img 并按规范命名",
                 how="命名规则 + 目录规则 + 压缩配置",
                 app="需要 app 加截图入口与图片处理", cost="低中"),
            dict(name="剪贴板流水", star=2, want="复制过的片段自动排队，稍后整理成笔记",
                 how="去重/合并规则 + 落地模板",
                 app="需要 app 加剪贴板监听（可关）", cost="中"),
        ]),
]


def card(d, x, y, w, h, item, accent):
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill="#111722", outline="#1F2937")
    stars = "★" * item["star"] + "☆" * (3 - item["star"])
    T(d, x + 20, y + 18, item["name"], F(HIRA, 18, 2), "#EFF4FF")
    T(d, x + w - 20, y + 22, stars, F(HIRA, 13), "#E8C15A", anchor="rt")
    T(d, x + 20, y + 50, "欲望点", F(HIRA, 11, 2), accent)
    T(d, x + 76, y + 50, item["want"], F(HIRA, 12), "#B9C6DC")
    T(d, x + 20, y + 80, "包内容", F(HIRA, 11, 2), accent)
    T(d, x + 76, y + 80, item["how"], F(HIRA, 12), "#B9C6DC")
    T(d, x + 20, y + 110, "app 改动", F(HIRA, 11, 2), "#8FA0BB")
    T(d, x + 76, y + 110, item["app"], F(HIRA, 12), "#93A3BE")
    T(d, x + 20, y + 140, "成本", F(HIRA, 11, 2), "#8FA0BB")
    T(d, x + 76, y + 140, item["cost"], F(HIRA, 12), "#93A3BE")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/plugins/plugin-directions-2.png"
    W = 1840
    H = 260 + sum(120 + len(f["items"]) // 2 * 190 + 60 for f in FAMILIES) + 200
    img, d = gt.page(W, H)
    T(d, 48, 34, "插件包 · 第二批方向（按「想要」而不是「效率」来想）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "上一批的病根：全是效率工具——解决麻烦，但不制造欲望。这一批按三件事分：成果拿得出手 / 有情绪陪伴 / 能把外面搬进来。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline="#E8C15A")
    T(d, W - 189, 68, "等你挑方向", F(HIRA, 13), "#E8C15A", anchor="mm")

    y = 130
    for fam in FAMILIES:
        rows = (len(fam["items"]) + 1) // 2
        block_h = 120 + rows * 190
        d.rounded_rectangle([40, y, W - 48, y + block_h], radius=16, fill="#0E131C", outline="#1B2534")
        d.rounded_rectangle([60, y + 22, 74, y + 62], radius=4, fill=fam["accent"])
        T(d, 92, y + 20, f"{fam['key']} · {fam['title']}", F(HIRA, 21, 2), "#EFF4FF")
        T(d, 94, y + 56, fam["note"], F(HIRA, 13), "#B9C6DC")
        for i, item in enumerate(fam["items"]):
            col, row = i % 2, i // 2
            x = 60 + col * 872
            card(d, x, y + 96 + row * 190, 856, 172, item, fam["accent"])
        y += block_h + 26

    d.rounded_rectangle([48, y + 6, W - 48, y + 166], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, y + 24, "如果让我押注，我会先做这三个", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, y + 54, "① 分享卡片：成本最低、成果立刻能看见（而且是唯一能把「主题」变现成外部价值的东西——卡片会用你当前主题的颜色和字体）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, y + 80, "② 写作音效：装上就有感觉，成本低；和主题同源（深林夜配雨声、炉火配柴火声）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, y + 106, "③ 桌面宠物：情绪价值最高，你之前对游戏化感兴趣，这条是那条线的延续（写得多→它长大）。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, y + 136, "剪藏收件箱我排第四——价值很高，但要动 HTML 清洗；双链图谱最贵，放最后。",
      F(HIRA, 13), "#8FA0BB")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
