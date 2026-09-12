#!/usr/bin/env python3
"""场景演示 v5：素材严格当前工作台 / 卡片封面=缩放图 / 设置里切换工作台 + 两级作用域规则。

用法: python3 scripts/make-plugin-scenarios-v5.py
"""

import importlib.util
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
sc = _load("make-plugin-scenarios")
v3 = _load("make-plugin-scenarios-v3")
F, T, T_mix = gt.F, gt.T, gt.T_mix
SONG, HIRA, MONO = gt.SONG, gt.HIRA, str(ROOT / "plugins-market/theme-sumi-paper/fonts/JetBrainsMono.ttf")
P, MD = sc.P, sc.MD
mix = sc.mix


def sheet(title, oneline, mock, steps, rules, out, accent, icon, mock_w=780):
    W, H = 1840, 880
    img, d = gt.page(W, H)
    T(d, 48, 30, title, F(SONG, 28, 0), "#EFF4FF")
    d.rounded_rectangle([48, 76, 60, 108], radius=3, fill=accent)
    T(d, 74, 80, oneline, F(HIRA, 16, 2), P["text"])
    d.rounded_rectangle([W - 300, 40, W - 48, 82], radius=20, fill="#161C26", outline=accent)
    T(d, W - 174, 61, "第五轮细改 · 未实现", F(HIRA, 12), accent, anchor="mm")
    gt.paste_win(img, mock, 48, 124, scale=0.60, radius=10, shadow=True)
    d.rounded_rectangle([48, 124, 48 + mock_w, 124 + int(mock.height * 0.60)],
                        radius=10, outline="#2A3648", width=1)
    T(d, 872, 124, "这个包到底在干什么", F(HIRA, 15, 2), accent)
    for i, (t, detail) in enumerate(steps):
        y = 158 + i * 112
        v3.step_box(d, 872, y, 920, 100, i + 1, t, detail, accent, icon if i == 0 else None)
        if i < len(steps) - 1:
            v3.arrow(d, 1320, y + 100 + 6, 26, accent)
    top = 158 + len(steps) * 112 + 14
    h = 62 + len(rules) * 26 + 24
    d.rounded_rectangle([872, top, 1792, top + h], radius=14, fill="#111722", outline="#1F2937")
    T(d, 894, top + 18, "插件规则 · 隔离与作用域", F(HIRA, 15, 2), "#8FB8FF")
    for i, line in enumerate(rules):
        T(d, 894, top + 50 + i * 26, line, F(HIRA, 12.5), "#B9C6DC")
    img.save(out)
    print(out)


def win_base():
    return review.render_window(P).copy()


# 素材库 v5：严格当前工作台
def scen_assets():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rounded_rectangle([14, 132, 42, 160], radius=8, fill=P["card"])
    d.rounded_rectangle([14, 178, 42, 206], radius=8, outline=P["line"])
    d.rounded_rectangle([14, 224, 42, 252], radius=8, fill=mix(P["bg"], MD["h1"], 0.28), outline=MD["h1"])
    T(d, 28, 238, "▦", F(HIRA, 13), MD["h1"], anchor="mm")
    d.rectangle([820, 0, 1300, 800], fill=P["bg"])
    d.line([(820, 0), (820, 800)], fill=P["line"])
    # 标题只读显示当前工作台（切换在设置里）
    T(d, 846, 12, "素材 · origin", F(HIRA, 15, 2), P["text"])
    T(d, 1090, 16, "切换工作台在 设置 ⌘,", F(HIRA, 10), P["--text-secondary"])
    T(d, 846, 40, "本工作台 source/ 资源 · 128 个 · 3 个未被引用（只算本工作台）",
      F(HIRA, 11), P["--text-secondary"])
    d.rounded_rectangle([846, 64, 1274, 96], radius=9, fill=P["card"], outline=P["line"])
    T(d, 862, 72, "搜索本工作台素材（文件名 / 尺寸）", F(HIRA, 11), P["--text-secondary"])
    for i in range(6):
        col, row = i % 3, i // 3
        x, y = 846 + col * 146, 110 + row * 130
        d.rounded_rectangle([x, y, x + 132, y + 82], radius=8,
                            fill=mix(P["bg"], MD["h3"], 0.20), outline=P["line"])
        T(d, x + 10, y + 56, f"09-1{i}-素材", F(HIRA, 10), P["text"])
        if i in (1, 4):
            d.rounded_rectangle([x + 84, y + 8, x + 124, y + 28], radius=6,
                                fill=mix(P["bg"], MD["bold"], 0.30))
            T(d, x + 104, y + 18, "引用 2", F(HIRA, 9), MD["bold"], anchor="mm")
    d.rounded_rectangle([846, 382, 1274, 470], radius=10, fill=P["card"], outline=P["line"])
    T(d, 862, 394, "09-11-手绘线稿.png", F(HIRA, 12, 2), P["text"])
    T(d, 862, 418, "本工作台内被 2 篇引用：周记 09 · 收件箱", F(HIRA, 10), P["--text-secondary"])
    d.rounded_rectangle([862, 436, 1002, 462], radius=9, fill=mix(P["bg"], MD["h1"], 0.30), outline=MD["h1"])
    T(d, 932, 449, "插入到光标处", F(HIRA, 11), MD["h1"], anchor="mm")
    T(d, 1030, 449, "⋯  在 Finder 显示 · 整理历史图（二级）", F(HIRA, 10), P["--text-secondary"])
    # 剪贴板 / 外部拖入 → 复制进本工作台
    d.rounded_rectangle([846, 486, 1274, 556], radius=10, fill=mix(P["bg"], MD["h2"], 0.14), outline=MD["h2"])
    T(d, 862, 496, "从外部或别的工作台拖进来的图 → 复制进本工作台", F(HIRA, 11, 2), MD["h2"])
    T(d, 862, 518, "不建立跨工作台引用：每个工作台都能独立搬走 / 备份 / 换机器", F(HIRA, 10), P["--text-secondary"])
    T(d, 862, 536, "引用计数、未被引用筛选、删除提示 —— 全部只算本工作台", F(HIRA, 10), P["--text-secondary"])
    T_mix(d, 360, 420, "![手绘线稿](img/09-11-手绘线稿.png)", F(MONO, 13), F(HIRA, 13), MD["h1"])
    d.rounded_rectangle([346, 452, 800, 502], radius=10, fill=mix(P["bg"], MD["h1"], 0.16), outline=MD["h1"])
    T(d, 362, 462, "已存入 origin/source/image/09-11-手绘线稿.png", F(HIRA, 11.5), MD["h1"])
    T(d, 362, 482, "⌘Z 撤销　·　无需「导入」按钮", F(HIRA, 10), P["--text-secondary"])
    return win


# 卡片墙 v5：封面 = 正文首图缩放图
def scen_cards():
    win = win_base()
    d = ImageDraw.Draw(win)
    d.rectangle([330, 0, 1300, 800], fill=P["bg"])
    T(d, 358, 12, "卡片墙 · 只显示笔记", F(HIRA, 15, 2), P["text"])
    T(d, 560, 16, "工作台 origin（切换在设置里）", F(HIRA, 10), P["--text-secondary"])
    for i, t in enumerate(["树", "卡片"]):
        x = 880 + i * 76
        d.rounded_rectangle([x, 8, x + 68, 38], radius=9,
                            fill=P["card"] if i == 1 else None, outline=None if i == 1 else P["line"])
        T(d, x + 34, 23, t, F(HIRA, 11), P["text"] if i == 1 else P["--text-secondary"], anchor="mm")
    for i, t in enumerate(["最近", "带图", "未完成"]):
        x = 1046 + i * 80
        d.rounded_rectangle([x, 8, x + 72, 38], radius=9,
                            fill=P["card"] if i == 0 else None, outline=None if i == 0 else P["line"])
        T(d, x + 36, 23, t, F(HIRA, 11), P["text"] if i == 0 else P["--text-secondary"], anchor="mm")
    cards = [("《账目》产品设计文档", "记账的边界与验收标准…", MD["h1"], 0.72, True),
             ("周记 09", "这周把主题做完，深林夜…", MD["h2"], 0.35, True),
             ("markdown 有哪些语法", "标题、粗体、列表、表格…", MD["h3"], 1.0, False),
             ("配色评审记录", "青瓷灰 / 藕荷 / 沙金…", MD["math"], 0.18, True)]
    for i, (title, summary, color, progress, has_img) in enumerate(cards):
        col, row = i % 2, i // 2
        x, y = 358 + col * 462, 56 + row * 320
        d.rounded_rectangle([x, y, x + 442, y + 300], radius=14, fill=P["card"], outline=P["line"])
        # 封面：正文首图的缩放图（等比裁剪填满）
        cov = [x, y, x + 442, y + 132]
        d.rounded_rectangle(cov, radius=14, fill=mix(P["bg"], color, 0.22))
        if has_img:
            d.rectangle([x + 8, y + 8, x + 434, y + 124], fill=mix(P["bg"], color, 0.45))
            for k in range(6):
                d.rounded_rectangle([x + 40 + k * 62, y + 34, x + 86 + k * 62, y + 100],
                                    radius=6, fill=mix(P["bg"], color, 0.75))
            T(d, x + 12, y + 104, "正文首图 · 等比缩放裁剪", F(HIRA, 9), P["text"])
        else:
            T(d, x + 12, y + 100, "无图 · 用纸色块", F(HIRA, 9), P["--text-secondary"])
        T(d, x + 16, y + 148, title, F(HIRA, 15, 2), P["text"])
        T(d, x + 16, y + 176, summary, F(HIRA, 12), P["--text-secondary"])
        d.rounded_rectangle([x + 16, y + 206, x + 426, y + 214], radius=4, fill=P["card2"])
        d.rounded_rectangle([x + 16, y + 206, x + 16 + int(410 * progress), y + 214], radius=4, fill=color)
        T(d, x + 16, y + 222, f"上次读到 {int(progress * 100)}%　·　1,240 字", F(HIRA, 10), P["--text-secondary"])
        for j, (label, c2) in enumerate([("继续写", color), ("加星", P["--text-secondary"]), ("归档", P["--text-secondary"])]):
            bx = x + 16 + j * 96
            d.rounded_rectangle([bx, y + 250, bx + 84, y + 274], radius=8, outline=c2 if j == 0 else P["line"])
            T(d, bx + 42, y + 262, label, F(HIRA, 10), c2 if j == 0 else P["--text-secondary"], anchor="mm")
    d.rounded_rectangle([358, 700, 1272, 758], radius=10, fill=mix(P["bg"], MD["h2"], 0.12), outline=MD["h2"])
    T(d, 374, 710, "封面 = 笔记正文里第一张图的缩放图（等比裁剪）；没有图就用纸色块", F(HIRA, 11, 2), MD["h2"])
    T(d, 374, 732, "素材仍然只在「素材」面板里；卡片墙只回答：我写过什么、哪些没读完", F(HIRA, 10), P["--text-secondary"])
    return win


# 设置里的工作台切换
def scen_settings():
    img = Image.new("RGB", (780, 800), P["bg"])
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, 780, 60], fill=P["card"])
    T(d, 24, 18, "设置", F(HIRA, 16, 2), P["text"])
    T(d, 90, 22, "通用", F(HIRA, 12), MD["h1"])
    T(d, 150, 22, "编辑", F(HIRA, 12), P["--text-secondary"])
    T(d, 210, 22, "插件", F(HIRA, 12), P["--text-secondary"])
    y = 84
    T(d, 24, y, "工作台", F(HIRA, 15, 2), P["text"])
    d.rounded_rectangle([24, y + 26, 756, y + 96], radius=10, fill=P["card"], outline=MD["h1"])
    T(d, 40, y + 38, "当前：origin", F(HIRA, 13, 2), P["text"])
    T(d, 40, y + 60, "/Users/gzhysu/Desktop/origin", F(MONO, 10), P["--text-secondary"])
    d.rounded_rectangle([600, y + 40, 740, y + 70], radius=9, fill=mix(P["bg"], MD["h1"], 0.30), outline=MD["h1"])
    T(d, 670, y + 55, "在 Finder 显示", F(HIRA, 10), MD["h1"], anchor="mm")
    y += 120
    T(d, 24, y, "最近工作台（点一下切换整个工作环境）", F(HIRA, 12, 2), P["--text-secondary"])
    ws = [("origin", "/Desktop/origin", True, "128 素材"),
          ("note", "/Desktop/note", False, "42 素材"),
          ("html_exercise", "/Desktop/html_exercise", False, "18 素材"),
          ("book", "/Desktop/我的文档/book", False, "7 素材")]
    for i, (name, path, cur, meta) in enumerate(ws):
        yy = y + 24 + i * 62
        d.rounded_rectangle([24, yy, 756, yy + 54], radius=10,
                            fill=mix(P["bg"], MD["h1"], 0.10) if cur else P["card"],
                            outline=MD["h1"] if cur else P["line"])
        d.ellipse([40, yy + 18, 58, yy + 36], fill=MD["insert"] if cur else P["card2"], outline=P["line"])
        T(d, 70, yy + 8, name, F(HIRA, 12.5, 2), P["text"])
        T(d, 70, yy + 30, path, F(MONO, 9.5), P["--text-secondary"])
        T(d, 560, yy + 18, meta, F(HIRA, 10), P["--text-secondary"])
        if cur:
            T(d, 700, yy + 18, "当前", F(HIRA, 10, 2), MD["h1"])
    yy = y + 24 + len(ws) * 62 + 8
    d.rounded_rectangle([24, yy, 380, yy + 46], radius=10, outline=P["line"])
    T(d, 202, yy + 23, "打开其他文件夹作为工作台…", F(HIRA, 11), P["text"], anchor="mm")
    T(d, 24, yy + 66, "切换后：素材、卡片墙、索引全部跟着切；主题 / 排版偏好 / 快捷键保持全局。",
      F(HIRA, 10.5), P["--text-secondary"])
    T(d, 24, yy + 90, "每个工作台都是独立环境——可以单独搬走、备份、换机器。", F(HIRA, 10.5), P["--text-secondary"])
    return img


def main():
    outdir = ROOT / "docs/proposals/plugins"
    sheet("场景 ① · 素材库 v5（严格当前工作台）",
          "一句话：素材只算当前工作台——引用计数、未引用筛选、删除提示，全部只看本工作台。",
          scen_assets(),
          [("唯一触发：拖进来 / 粘贴",
            ["存进「当前工作台 / source/image」，按「日期-描述」命名，编辑区给一条可撤销提示"]),
           ("面板头顶只写当前工作台",
            ["「素材 · origin」是只读标签；切换工作台去 设置 ⌘,（不再面板里切）"]),
           ("跨库拖入 = 复制进来",
            ["不建立跨工作台引用：每个工作台都能独立搬走 / 备份 / 换机器"])],
          ["作用域：工作台级 —— 只索引当前工作台",
           "只读：复用现有 source/ 扫描（不新建数据库）",
           "只写：当前工作台 source/ 的新建与重命名，可撤销",
           "跨库：一律复制，不建立跨工作台引用"],
          outdir / "v5-assets.png", MD["h1"], v3.icon_file)
    sheet("场景 ② · 卡片墙 v5（封面 = 正文首图缩放图）",
          "一句话：卡片封面直接取笔记正文里第一张图的缩放图（等比裁剪），没有图就用纸色块。",
          scen_cards(),
          [("侧栏顶部切「树 / 卡片」",
            ["卡片墙只显示当前工作台的笔记；工作台切换在设置里，不在这里"]),
           ("封面 = 正文首图 · 等比缩放裁剪",
            ["无图 → 纸色块；封面只读笔记内容，不读取素材面板的选择"]),
           ("悬浮就能继续写",
            ["继续写 / 加星 / 归档；长文显示「上次读到 72%」"])],
          ["作用域：工作台级（与素材库同一个当前工作台）",
           "只读：复用目录索引与图片注册表；星标存本机偏好",
           "不写：不移动、不改名、不改笔记内容",
           "卸载即干净：切回文件树，一切照旧"],
          outdir / "v5-cards.png", MD["h2"], v3.icon_grid)
    sheet("场景 ③ · 设置里切换工作台（插件两级作用域）",
          "一句话：工作台切换是全局设置项；插件必须声明自己是「工作台级」还是「全局级」。",
          scen_settings(),
          [("设置 → 工作台：当前 + 最近列表",
            ["点一下切换整个工作环境：素材、卡片墙、索引全部跟着切"]),
           ("工作台级插件（跟工作台走）",
            ["素材库 · 卡片墙 · 索引类 —— 换工作台就换一整套数据"]),
           ("全局级插件（跨工作台共享）",
            ["主题 · 排版偏好 · 阅读专注态 · 快捷键 —— 换工作台不变"])],
          ["插件清单必须声明 scope：workspace / global",
           "声明 workspace 的插件：只能读当前工作台，禁止跨库引用",
           "声明 global 的插件：只存本机偏好，不读笔记内容",
           "切换工作台时：workspace 插件重新加载，global 插件不动"],
          outdir / "v5-settings.png", MD["h3"], v3.icon_leaf if hasattr(v3, "icon_leaf") else v3.icon_window, mock_w=470)


if __name__ == "__main__":
    main()
