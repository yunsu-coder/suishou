#!/usr/bin/env python3
"""游戏化主题 · 动效预览（MP4 + GIF），评审用；不安装、不进主题列表。

用法: python3 scripts/make-game-themes-motion.py <outdir>
输出: <outdir>/motion.mp4, <outdir>/guild-loop.gif
"""

import importlib.util
import math
import subprocess
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("gt", HERE / "make-game-themes.py")
gt = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gt)

FPS = 24
VW, VH = 1400, 1010
WX, WY = 50, 152
TITLE_BG = "#0B0E14"
SONG, HIRA, MENLO = gt.SONG, gt.HIRA, gt.MENLO


def F(p, s, i=0):
    return gt.F(p, s, i)


def clamp(v, lo=0.0, hi=1.0):
    return max(lo, min(hi, v))


def ramp(t, a, b):
    return clamp((t - a) / max(1e-6, b - a))


def ease(v):
    return v * v * (3 - 2 * v)


def canvas(title, sub, accent):
    img = Image.new("RGB", (VW, VH), TITLE_BG)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([50, 44, 60, 96], radius=5, fill=accent)
    d.text((78, 44), title, font=F(SONG, 30, 0), fill="#EFF4FF")
    d.text((80, 88), sub, font=F(HIRA, 15), fill="#8FA0BB")
    return img, d


def caption_bar(d, accent, text, hint=""):
    y = 968
    d.rectangle([0, y - 14, VW, VH], fill="#10141C")
    d.rounded_rectangle([50, y - 4, 56, y + 26], radius=3, fill=accent)
    d.text((72, y), text, font=F(HIRA, 14), fill="#D7E1F0")
    if hint:
        d.text((VW - 50, y), hint, font=F(MENLO, 12), fill="#5F6E86", anchor="rt")


def guild_frame(t):
    typing = ramp(t, 0.02, 0.34)
    xp = 0.62 + 0.38 * ease(ramp(t, 0.32, 0.68))
    up = t >= 0.72
    flash = clamp(1 - abs(t - 0.74) / 0.07)
    words = int(1842 + (2602 - 1842) * ease(ramp(t, 0.3, 0.72)))
    img = gt.render_guild(8, anim=dict(
        xp_frac=min(1.0, xp), level_bump=up, reveal=int(typing * len("- [ ] 撰写营地物资清单")),
        toast=ramp(t, 0.76, 0.9), flag_gold=t > 0.9, flash=flash,
        glow=0.85 + 0.15 * math.sin(t * math.pi * 8),
        count=f"{words:,} 字",
    ))
    if t < 0.5:
        cap = "写作中：光标推进、字数实时累计，侧栏委托进度随之增长"
    elif t < 0.72:
        cap = "写满委托：经验条上涨 → 升级，状态栏同步刷新"
    elif t < 0.88:
        cap = "成就横幅滑入 + 升级高亮，不打断输入、不阻塞编辑"
    else:
        cap = "连更 7 天：公会旗帜镀金（彩蛋），全程本地计算"
    return img, cap, "#D9A441"


def garden_frame(t):
    grow = 0.45 + 0.55 * ease(ramp(t, 0.02, 0.45))
    bloom = -0.4 + 2.0 * ease(ramp(t, 0.35, 0.8))
    words = int(612 + (1240 - 612) * ease(ramp(t, 0.05, 0.7)))
    img = gt.render_garden(8, anim=dict(
        growth=grow, bloom=bloom, butterfly=(t * 1.15) % 1.0,
        toast=ramp(t, 0.72, 0.86), count=f"{words:,} 字",
    ))
    if t < 0.4:
        cap = "写作 = 浇水：植物随字数长高，进度写回主题"
    elif t < 0.72:
        cap = "里程碑开花：花苞一瓣瓣展开，稀有花色随机"
    else:
        cap = "开花记录进花园面板，蝴蝶彩蛋出现（减少动态效果时静止）"
    return img, cap, "#5F8468"


def foundry_frame(t):
    p = ease(ramp(t, 0.05, 0.62))
    filled = int(11 + 13 * p)
    coined = int(1284 + (1500 - 1284) * p)
    words = int(1204 + (1408 - 1204) * p)
    img = gt.render_foundry(8, anim=dict(
        sample=clamp(t / 0.16), filled=filled, coined=coined,
        toast=ramp(t, 0.74, 0.88), count=f"{words:,} 字",
    ))
    if t < 0.3:
        cap = "每写 1,000 字铸一枚铅字，字盘逐格填满"
    elif t < 0.74:
        cap = "字模抽屉逐个点亮，试印样张同步更新"
    else:
        cap = "集满字盘 → 解锁主题专属标题字体，立刻应用到标题与预览"
    return img, cap, "#C08A4A"


def intro_frames():
    for i in range(int(2.0 * FPS)):
        t = i / (2.0 * FPS)
        img = Image.new("RGB", (VW, VH), TITLE_BG)
        d = ImageDraw.Draw(img)
        d.rounded_rectangle([50, 44, 60, 96], radius=5, fill="#7FD1C0")
        d.text((78, 44), "游戏化主题 · 动效预览", font=F(SONG, 30, 0), fill="#EFF4FF")
        d.text((80, 88), "主题不只是皮肤：写作会推进主题自带的玩法循环。", font=F(HIRA, 15), fill="#8FA0BB")
        items = [("A · 冒险者公会", "委托 / 经验 / 称号 / Boss", "#D9A441"),
                 ("B · 纸上花园", "浇水 / 生长 / 开花 / 收藏", "#5F8468"),
                 ("C · 铸字工坊", "铸字 / 字盘 / 解锁专属字体", "#C08A4A")]
        for k, (n, s, col) in enumerate(items):
            y = 230 + k * 210
            x = 120 + int(30 * math.sin((t * 2 + k * 0.3) * math.pi))
            d.rounded_rectangle([x, y, x + 1160, y + 160], radius=16, fill="#121824", outline="#232F42")
            d.rounded_rectangle([x + 34, y + 40, x + 44, y + 120], radius=5, fill=col)
            d.text((x + 70, y + 44), n, font=F(HIRA, 24, 2), fill="#EFF4FF")
            d.text((x + 72, y + 92), s, font=F(HIRA, 15), fill="#93A3BE")
        d.text((120, 900), "以下动画全部来自主题包声明：动效只用 opacity / transform，尊重系统「减少动态效果」。",
               font=F(HIRA, 14), fill="#5F6E86")
        yield img


def outro_frames():
    wins = [(gt.render_guild(8), "A · 冒险者公会", "#D9A441"),
            (gt.render_garden(8), "B · 纸上花园", "#5F8468"),
            (gt.render_foundry(8), "C · 铸字工坊", "#C08A4A")]
    for i in range(int(2.5 * FPS)):
        t = i / (2.5 * FPS)
        img, d = canvas("三个方向，请挑一个继续深化", "选定后我会做主题包（字体 / 语义图标 / 动效 / 彩蛋）并等你人工审核，通过后才进入主题列表。",
                        "#7FD1C0")
        for k, (win, name, col) in enumerate(wins):
            x = 50 + k * 448
            gt.paste_win(img, win, x, 200, scale=0.336, radius=6, shadow=False)
            d.rounded_rectangle([x, 200, x + 437, 469], radius=6, outline=col, width=2)
            d.text((x, 500), name, font=F(HIRA, 16, 2), fill="#EFF4FF")
        d.text((50, 600), "实现成本：主题包负责视觉与节奏；玩法进度需要一个本地小引擎（字数 / 保存 / 连更 → 经验），",
               font=F(HIRA, 14), fill="#8FA0BB")
        d.text((50, 630), "不联网、无后台进程，状态栏与侧栏各加一个轻量面板，不会造成输入卡顿。",
               font=F(HIRA, 14), fill="#8FA0BB")
        d.text((50, 700), "硬门槛不变：专属字体 + 每个语义槽位专属图标 + 动效 + 彩蛋 + 对比度 / 体积达标，缺一不进列表。",
               font=F(HIRA, 14), fill="#7FD1C0")
        d.text((50, 800), "告诉我 A / B / C（或组合 / 修改意见），我再动手做正式主题包。",
               font=F(HIRA, 20, 2), fill="#EFF4FF")
        caption_bar(d, "#7FD1C0", "待人工审核 · 未安装 · 未进入主题列表", "MarkNote themes")
        yield img


def make_frames():
    segs = [(guild_frame, 6.0), (garden_frame, 6.0), (foundry_frame, 6.0)]
    for img in intro_frames():
        yield img
    for fn, dur in segs:
        n = int(dur * FPS)
        accent = fn(0.0)[2]
        for i in range(n):
            t = i / n
            win, cap, _ = fn(t)
            img, d = canvas({guild_frame: "A · 冒险者公会 · 写作 = 接委托",
                             garden_frame: "B · 纸上花园 · 写作 = 浇水",
                             foundry_frame: "C · 铸字工坊 · 写作 = 铸字"}[fn],
                            "动效预览：数据全部本地计算，动画只用 opacity / transform", accent)
            slide = int(30 * (1 - ease(clamp(t / 0.06))))
            gt.paste_win(img, win, WX, WY + slide, radius=12, shadow=True)
            caption_bar(d, accent, cap, "MarkNote · review build")
            yield img
    for img in outro_frames():
        yield img


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else "docs/proposals/game")
    outdir.mkdir(parents=True, exist_ok=True)
    mp4 = outdir / "motion.mp4"
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
           "-s", f"{VW}x{VH}", "-r", str(FPS), "-i", "-", "-an",
           "-c:v", "libx264", "-preset", "medium", "-crf", "20",
           "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(mp4)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    frames = 0
    for img in make_frames():
        proc.stdin.write(img.tobytes())
        frames += 1
    proc.stdin.close()
    proc.wait()
    print(f"{mp4} · {frames} frames · {mp4.stat().st_size / 1e6:.1f} MB")

    gif = outdir / "guild-loop.gif"
    gif_frames = []
    for i in range(int(6.0 * 12)):
        t = i / (6.0 * 12)
        win, cap, accent = guild_frame(t)
        img, d = canvas("A · 冒险者公会 · 写作 = 接委托",
                        "写作 → 经验 → 升级 / 成就（动效预览）", accent)
        gt.paste_win(img, win, WX, WY, radius=12, shadow=True)
        caption_bar(d, accent, cap, "MarkNote · review")
        gif_frames.append(img.resize((760, 548), Image.LANCZOS))
    gif_frames[0].save(gif, save_all=True, append_images=gif_frames[1:], duration=83,
                       loop=0, optimize=True)
    print(f"{gif} · {gif.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
