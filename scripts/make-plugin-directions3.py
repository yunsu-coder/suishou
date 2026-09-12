#!/usr/bin/env python3
"""插件包方向提案图 · 第三批：观感（排版/字体）与笔记库健康（版本/整理）。

用法: python3 scripts/make-plugin-directions3.py [输出.png]
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
SONG, HIRA, MENLO, ZH = gt.SONG, gt.HIRA, gt.MENLO, gt.SONG

GROUPS = [
    dict(key="①", title="观感 · 你每天盯着的那一屏", accent="#7FD1C0",
         note="主题证明了你在意「看着舒服」。这一类接着往里做：排版、字体、代码样式——都不改内容，只改你怎么看到它。",
         items=[
             dict(name="中文排版规则包", star=3,
                  want="同一篇笔记，立刻变得「像出版物」：标点挤压、避头尾、中英之间自动留白、引号统一",
                  how="规则集（可逐条开关）+ 与主题联动（深林夜用紧凑行距、沙金用宽松行距）",
                  app="预览层已有 CSS 钩子，成本主要在规则正确性；编辑器内可选预览",
                  cost="低中", gate="每条规则必须给「改前/改后」对照，禁止改动正文内容"),
             dict(name="字体包", star=3,
                  want="正文、标题、等宽各挑一套：把「读起来累不累」交给自己定",
                  how="字体包（OFL 字体 + 字重映射 + 行高/字距建议值），可叠加在当前主题上",
                  app="需要把「字体」从主题里解耦成一层可叠加配置（现在绑在主题包上）",
                  cost="中", gate="必须标授权（OFL/系统）、给 3 档字号预览、单字体 ≤12MB"),
             dict(name="代码样式包", star=2,
                  want="代码块、行号、终端块单独换配色和留白，不用为了代码去换整个主题",
                  how="覆盖 --code-bg / --hl-* / 行号样式",
                  app="几乎不用（渲染层变量已经存在）",
                  cost="低", gate="高亮色在代码底 ≥3.0:1，行号不抢正文"),
             dict(name="图注与编号包", star=2,
                  want="图片自动编号（图 1 / 图 2）、表格编号、引用「见图 3」",
                  how="编号规则 + 交叉引用语法 + 渲染样式",
                  app="需要渲染层支持编号与引用解析",
                  cost="中", gate="编号必须可预测（重排不跳号），交叉引用要有失效提示"),
         ]),
    dict(key="②", title="笔记库健康 · 真出事会心疼的东西", accent="#8FB8FF",
         note="这类不提升写作，但决定「敢不敢把重要的东西放进去」。你现在只有目录 + 简易版本历史。",
         items=[
             dict(name="本地版本快照包", star=3,
                  want="每 10 分钟 / 每次大改自动留快照，能对比、能一键回到某个时间点",
                  how="快照触发规则 + 保留策略（按天/按周折叠）+ 差异视图",
                  app="已有 .versions 目录和版本面板，需要加触发与保留策略",
                  cost="低中", gate="快照只增不改、可一键导出、绝不自动删用户文件"),
             dict(name="库整理包", star=2,
                  want="一键把乱掉的笔记库整理干净：按日期/关键词归档、文件名规范化、空目录清理",
                  how="规则集（匹配 → 动作）+ 变更预览（先看 diff 再执行）+ 撤销记录",
                  app="需要文件移动/重命名 + 预览确认（危险操作）",
                  cost="中", gate="必须先出 diff 再执行；每一步可撤销；绝不批量删除内容"),
             dict(name="备份包（异地）", star=2,
                  want="定时把库打包到指定目录 / 移动硬盘 / 网盘目录，带校验",
                  how="目标目录 + 频率 + 保留份数 + 校验和",
                  app="需要定时任务与打包（本地，不上传任何服务器）",
                  cost="低中", gate="必须校验完整性、失败要显眼提示，不静默失败"),
             dict(name="隐私分级包", star=2,
                  want="给个别笔记上锁（打开要密码），其余照常",
                  how="加密标记 + 密码策略 + 锁定时在列表里显示为「已锁」",
                  app="需要单文件加密（本地密钥派生）",
                  cost="中高", gate="加密算法与参数必须写明；忘密码不可恢复要说清楚"),
         ]),
    dict(key="③", title="写字的手感 · 让「记一笔」变成 1 秒", accent="#E8C15A",
         note="不是模板库那种死文字，而是把重复动作变成一次按键：日期、序号、今日条目、常用结构。",
         items=[
             dict(name="快捷片段包", star=2,
                  want="输入 /date /time /seq 就落地成日期、时间、自动序号；常用结构一键插入",
                  how="触发词 + 变量（日期/时间/序号/文件名/当前大纲）+ 落地样式",
                  app="需要给片段加「变量」支持（现在是纯文本）",
                  cost="低", gate="触发词不得与正常输入冲突；变量必须有明确格式"),
             dict(name="日志工作流包", star=2,
                  want="一个快捷键：建/打开今天的日记，自动带上日期标题和昨天的尾巴",
                  how="命名规则 + 模板 + 跳转规则",
                  app="需要快捷键动作与「打开或新建」逻辑",
                  cost="低中", gate="文件命名必须有唯一规则，重复触发不产生第二个文件"),
             dict(name="收集箱工作流", star=2,
                  want="全局快捷键随手记一句，统一落进 inbox，之后再整理",
                  how="落地位置 + 追加格式（时间戳）+ 整理提示",
                  app="需要全局快捷键与追加写入",
                  cost="低中", gate="追加不得破坏原有内容；冲突要有提示"),
             dict(name="跨笔记引用包", star=2,
                  want="引用另一篇笔记的某个段落，源文改了这边能看到「已过期」",
                  how="引用语法 + 失效检测 + 重新同步动作",
                  app="需要解析与失效追踪（可与双链共用一套索引）",
                  cost="中高", gate="失效必须显式提示，禁止静默显示旧内容"),
         ]),
]


def card(d, x, y, w, h, item, accent):
    d.rounded_rectangle([x, y, x + w, y + h], radius=14, fill="#111722", outline="#1F2937")
    stars = "★" * item["star"] + "☆" * (3 - item["star"])
    T(d, x + 20, y + 16, item["name"], F(HIRA, 18, 2), "#EFF4FF")
    T(d, x + w - 20, y + 20, stars, F(HIRA, 13), "#E8C15A", anchor="rt")
    T(d, x + 20, y + 48, "想要", F(HIRA, 11, 2), accent)
    T(d, x + 66, y + 48, item["want"], F(HIRA, 12), "#B9C6DC")
    T(d, x + 20, y + 78, "包内容", F(HIRA, 11, 2), accent)
    T(d, x + 66, y + 78, item["how"], F(HIRA, 12), "#B9C6DC")
    T(d, x + 20, y + 108, "app 改动", F(HIRA, 11, 2), "#8FA0BB")
    T(d, x + 66, y + 108, item["app"], F(HIRA, 12), "#93A3BE")
    T(d, x + 20, y + 134, "硬门槛", F(HIRA, 11, 2), "#E8C15A")
    T(d, x + 66, y + 134, item["gate"], F(HIRA, 12), "#93A3BE")
    T(d, x + w - 20, y + 134, "成本 " + item["cost"], F(HIRA, 11), "#8FA0BB", anchor="rt")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/proposals/plugins/plugin-directions-3.png"
    W = 1840
    H = 250 + sum(120 + ((len(g["items"]) + 1) // 2) * 178 + 40 for g in GROUPS) + 190
    img, d = gt.page(W, H)
    T(d, 48, 34, "插件包 · 第三批（观感 / 库健康 / 手感）", F(SONG, 30, 0), "#EFF4FF")
    T(d, 50, 84, "前两批的病根：都在「加功能」。这批换问法——你每天盯着什么（观感）、真出事会心疼什么（库）、哪些动作重复到烦（手感）。",
      F(HIRA, 15), "#93A3BE")
    d.rounded_rectangle([W - 330, 46, W - 48, 90], radius=20, fill="#161C26", outline="#E8C15A")
    T(d, W - 189, 68, "等你挑方向", F(HIRA, 13), "#E8C15A", anchor="mm")

    y = 126
    for g in GROUPS:
        rows = (len(g["items"]) + 1) // 2
        block_h = 118 + rows * 178
        d.rounded_rectangle([40, y, W - 48, y + block_h], radius=16, fill="#0E131C", outline="#1B2534")
        d.rounded_rectangle([60, y + 20, 74, y + 60], radius=4, fill=g["accent"])
        T(d, 92, y + 18, f"{g['key']} {g['title']}", F(HIRA, 21, 2), "#EFF4FF")
        T(d, 94, y + 54, g["note"], F(HIRA, 13), "#B9C6DC")
        for i, item in enumerate(g["items"]):
            col, row = i % 2, i // 2
            card(d, 60 + col * 872, y + 92 + row * 178, 856, 166, item, g["accent"])
        y += block_h + 24

    d.rounded_rectangle([48, y + 4, W - 48, y + 158], radius=12, fill="#141A24", outline="#243041")
    T(d, 70, y + 22, "我会先做这两个（都跟你已经在意的两件事直接相关）", F(HIRA, 15, 2), "#7FD1C0")
    T(d, 70, y + 52, "① 中文排版规则包：你对渲染和可读性提过好几次意见（Callout、公式、代码、列表颜色…）。排版规则是同一件事的下一层：不改内容，只让同一篇笔记看起来更像出版物。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, y + 78, "② 本地版本快照包：你说过「之后插件是渲染增强」，但真丢了东西是没法补的。这包几乎不用新能力（.versions 已有），做完你会更敢把重要的东西放进来。",
      F(HIRA, 13), "#B9C6DC")
    T(d, 70, y + 108, "字体包我排第三（要先把字体从主题里解耦，属于结构改动）；库整理包第四（涉及移动文件，必须先出 diff）。其余的先放着。",
      F(HIRA, 13), "#8FA0BB")
    T(d, 70, y + 134, "如果你对这三类都无感，那说明「随手」缺的可能已经不是插件，而是别的——那我们就把插件这条线收尾。",
      F(HIRA, 13), "#8FA0BB")
    img.save(out)
    print(out)


if __name__ == "__main__":
    main()
