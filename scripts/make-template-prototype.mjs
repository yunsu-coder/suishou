#!/usr/bin/env node
/**
 * 模板方案 D 的高保真原型图（用 Playwright + Chromium 渲染，不是示意图）。
 *
 * 用法：
 *   NODE_PATH=<runtime>/node_modules node scripts/make-template-prototype.mjs [输出目录]
 * 输出：
 *   docs/proposals/prototype-journal.png   日记（D1 元数据卡 + D2 行内控件）
 *   docs/proposals/prototype-todo.png      待办（D2 控件 + 看板预览）
 *   docs/proposals/prototype-class.png     课堂笔记（D3 块容器 + 公式/数据表）
 */

import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import { createRequire } from 'node:module'

// NODE_PATH 只对 CJS 生效：这里用 createRequire 走 require 解析 playwright
const require = createRequire(import.meta.url)
const { chromium } = require('playwright')

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..')
const OUT_DIR = process.argv[2] ? join(process.cwd(), process.argv[2]) : join(ROOT, 'docs/proposals')

/* ── 雾青主题的真实取值（取自 plugins-market/theme-misty-teal/theme.css） ── */
const CSS = `
:root{
  --bg:#FAFCF9; --surface:#FFFFFF; --text:#25302B; --text2:#5C6A63; --text3:#8A968F;
  --border:#E4EAE6; --accent:#1FA084; --accent-soft:#E4F0ED; --h1:#17735F; --h2:#2C6FB5;
  --code-bg:#F3F7F4; --warn:#C0563C;
  --ui:"Hiragino Sans GB","PingFang SC",-apple-system,sans-serif;
  --display:"Songti SC",serif; --mono:"SF Mono",Menlo,monospace;
}
*{box-sizing:border-box;margin:0;padding:0}
body{background:#EEF3F0;font-family:var(--ui);color:var(--text);padding:26px;
     display:flex;flex-direction:column;gap:26px;align-items:flex-start}
.cap{font-size:13px;color:var(--text2);margin-bottom:8px;font-weight:600}
.clear{background:transparent;font-family:var(--ui);font-size:12px;color:var(--text3);margin-bottom:6px}
.window{width:1420px;background:var(--bg);border-radius:12px;overflow:hidden;
        box-shadow:0 18px 50px rgba(23,60,52,.16),0 2px 6px rgba(23,60,52,.08)}
.titlebar{height:46px;display:flex;align-items:center;gap:14px;padding:0 16px;
          background:var(--surface);border-bottom:1px solid var(--border)}
.lights{display:flex;gap:8px}.lights i{width:12px;height:12px;border-radius:50%;display:block}
.lights i:nth-child(1){background:#FF5F57}.lights i:nth-child(2){background:#FEBC2E}
.lights i:nth-child(3){background:#28C840}
.tabs{display:flex;gap:6px}
.tab{padding:6px 13px;border-radius:7px;font-size:12.5px;color:var(--text2)}
.tab.active{background:var(--bg);color:var(--text);font-weight:600}
.body{display:grid;grid-template-columns:54px 216px 1fr 1fr;height:620px}
.rail{background:var(--surface);border-right:1px solid var(--border);display:flex;
      flex-direction:column;align-items:center;padding-top:12px;gap:16px;font-size:16px;color:var(--text3)}
.rail .on{color:var(--accent)}
.sidebar{background:var(--surface);border-right:1px solid var(--border);padding:12px 10px;font-size:12.5px}
.search{margin:0 0 12px;padding:6px 9px;border:1px solid var(--border);border-radius:7px;color:var(--text3)}
.group{color:var(--text3);font-size:11px;margin:10px 0 4px}
.file{display:flex;gap:7px;align-items:center;padding:5px 8px;border-radius:6px;color:var(--text2)}
.file.active{background:var(--accent-soft);color:var(--text);font-weight:600}
.pane{overflow:hidden;position:relative}
.editor{padding:20px 22px;font-family:var(--mono);font-size:12.5px;line-height:1.95;background:var(--bg)}
.preview{padding:20px 24px;background:var(--surface);border-left:1px solid var(--border);
         font-family:var(--display);font-size:14px;line-height:1.85}
h1{font-family:var(--display);font-size:21px;color:var(--h1);margin:2px 0 10px}
h2{font-family:var(--display);font-size:16px;color:var(--h2);margin:16px 0 6px}
.cmt{color:var(--text3)}
.k{color:var(--h1)}
.s{color:#2C6FB5}
.m{color:var(--text3)}
.fm{background:var(--code-bg);border-left:3px solid var(--accent);border-radius:6px;
    padding:8px 10px;color:var(--text2);font-size:11.8px;line-height:1.7}
/* ── D1 元数据卡（编辑器里把 front matter 变成控件） ── */
.meta{background:var(--accent-soft);border:1px solid #C9DFDA;border-radius:9px;
      padding:9px 11px;margin-bottom:14px;display:flex;gap:8px;flex-wrap:wrap;align-items:center}
.meta .label{font-size:10.5px;color:var(--text2);margin-right:2px}
.chip{background:#fff;border:1px solid #C9DFDA;border-radius:999px;padding:3px 9px;
      font-size:11.5px;color:var(--text);display:inline-flex;gap:5px;align-items:center}
.chip.accent{border-color:var(--accent);color:var(--h1)}
/* ── D2 行内控件 ── */
.ctl{display:inline-flex;align-items:center;gap:5px;vertical-align:1px}
.box{width:13px;height:13px;border:1.5px solid #9DB3AA;border-radius:3.5px;display:inline-block;position:relative}
.box.on{background:var(--accent);border-color:var(--accent)}
.box.on::after{content:"✓";color:#fff;font-size:10px;position:absolute;left:1.5px;top:-3px}
.due{background:#fff;border:1px solid var(--accent);border-radius:999px;padding:1px 7px;
     font-size:11px;color:var(--h1)}
.tag{color:var(--h2);font-size:11.5px}
.prog{height:6px;background:#E6EDEA;border-radius:99px;overflow:hidden;display:inline-block;vertical-align:middle}
.prog>span{display:block;height:100%;background:var(--accent)}
/* ── D3 块容器 ── */
.block{border-left:3px solid var(--accent);background:var(--code-bg);border-radius:0 8px 8px 0;
       padding:8px 12px;margin:10px 0}
.block .head{font-size:11px;color:var(--h1);font-weight:600;margin-bottom:4px}
/* ── 预览侧 ── */
.props{display:flex;gap:8px;flex-wrap:wrap;margin-bottom:14px}
.pchip{background:var(--accent-soft);border-radius:8px;padding:5px 10px;font-size:12px;font-family:var(--ui)}
.pchip b{color:var(--h1);font-weight:600}
.todo{display:flex;gap:8px;align-items:flex-start;margin:5px 0;font-family:var(--ui);font-size:13.5px}
.todo .box{margin-top:4px;flex:0 0 auto}
.done{color:var(--text3);text-decoration:line-through}
.kanban{display:grid;grid-template-columns:1fr 1fr 1fr;gap:10px;margin-top:12px}
.col{background:var(--bg);border:1px solid var(--border);border-radius:9px;padding:9px}
.col h3{font-family:var(--ui);font-size:12px;color:var(--text2);margin-bottom:7px}
.card{background:#fff;border:1px solid var(--border);border-radius:8px;padding:8px 9px;margin-bottom:7px;font-family:var(--ui)}
.card .t{font-size:12.5px;margin-bottom:6px}
.card .row{display:flex;gap:6px;flex-wrap:wrap}
.cornell{display:grid;grid-template-columns:1fr 1.35fr 1fr;gap:10px;margin-top:12px}
.cornell .cell{background:var(--bg);border:1px solid var(--border);border-radius:9px;padding:10px;font-family:var(--ui);font-size:12.5px}
.cornell .cell b{display:block;font-size:11px;color:var(--h1);margin-bottom:5px}
table{border-collapse:collapse;margin-top:10px;font-family:var(--ui);font-size:12.5px}
th,td{border:1px solid var(--border);padding:5px 12px;text-align:left}
th{background:var(--accent-soft);color:var(--h1)}
.note{font-family:var(--ui);font-size:11.5px;color:var(--text3);margin-top:10px}
/* 标注：细虚线 + 小字，不抢主体 */
.mark{position:relative;outline:1px dashed rgba(31,160,132,.75);outline-offset:4px;border-radius:6px}
.mark::after{content:attr(data-tag);position:absolute;right:-4px;top:-15px;font-family:var(--ui);
             font-size:10px;color:var(--accent);background:var(--bg);padding:0 4px}
`

const LIGHTS = `<div class="lights"><i></i><i></i><i></i></div>`

const RAIL = `
  <div class="rail">
    <div class="on">▤</div><div>▦</div><div>✦</div><div style="margin-top:auto">⚙</div>
  </div>`

function sidebar(active) {
  const files = [
    ['日记/2026-09-19.md', 'journal'],
    ['待办/看板-2026-W38.md', 'todo'],
    ['课堂笔记/线代-第4讲.md', 'class'],
  ]
  return `<div class="sidebar">
    <div class="search">搜索文件</div>
    <div class="group">工作台 origin</div>
    ${files.map(([name, key]) =>
      `<div class="file ${key === active ? 'active' : ''}"><span>▢</span><span>${name}</span></div>`).join('')}
    <div class="group">source</div>
    <div class="file"><span>▾</span><span>image / mp4 / pdf</span></div>
  </div>`
}

function windowShell(active, tabs, editorHTML, previewHTML) {
  return `<div class="window">
    <div class="titlebar">${LIGHTS}
      <div class="tabs">${tabs.map(([name, key]) =>
        `<div class="tab ${key === active ? 'active' : ''}">${name}</div>`).join('')}</div>
    </div>
    <div class="body">
      ${RAIL}
      ${sidebar(active)}
      <div class="pane editor">${editorHTML}</div>
      <div class="pane preview">${previewHTML}</div>
    </div>
  </div>`
}

/* ───────────────────────── 一、日记 ───────────────────────── */

const journalEditor = `
<div class="meta mark" data-tag="D1 元数据卡（点控件改，不碰 YAML）">
  <span class="label">属性</span>
  <span class="chip accent">📅 2026-09-19 周六</span>
  <span class="chip">☀️ 晴</span>
  <span class="chip">🙂 心情</span>
  <span class="chip">#日记</span><span class="chip">#周记</span>
</div>
<div><span class="k"># 2026-09-19 周六（晴）</span></div>
<div>&nbsp;</div>
<div><span class="k">## 三件好事</span></div>
<div class="mark" data-tag="D2 行内控件">
  <span class="ctl"><span class="box on"></span> 早起跑了 3 km</span><br>
  <span class="ctl"><span class="box"></span> 把实验报告写完
    <span class="due">📅 09-20</span> <span class="tag">#论文</span></span><br>
  <span class="ctl"><span class="box"></span> 晚上给妈妈打电话</span>
</div>
<div>&nbsp;</div>
<div class="ctl">进度 :: <span class="prog" style="width:110px"><span style="width:33%"></span></span>
  <span class="m">1/3（自动统计）</span></div>
<div>&nbsp;</div>
<div><span class="k">## 今日复盘</span></div>
<div><span class="m">- 做成了：</span></div>
<div><span class="m">- 卡住了：</span></div>
<div>&nbsp;</div>
<div class="fm">---<br>type: 日记 <span class="cmt">← 文件里仍是普通 front matter</span><br>
date: 2026-09-19<br>weather: 晴<br>mood: 🙂<br>tags: [日记, 周记]<br>---</div>
`

const journalPreview = `
<div class="props">
  <span class="pchip"><b>日期</b> 2026-09-19 周六</span>
  <span class="pchip"><b>天气</b> 晴</span>
  <span class="pchip"><b>心情</b> 🙂</span>
  <span class="pchip"><b>标签</b> 日记 · 周记</span>
</div>
<h1>2026-09-19 周六（晴）</h1>
<h2>三件好事</h2>
<div class="todo"><span class="box on"></span><span class="done">早起跑了 3 km</span></div>
<div class="todo"><span class="box"></span><span>把实验报告写完
  <span class="due">📅 09-20</span> <span class="tag">#论文</span></span></div>
<div class="todo"><span class="box"></span><span>晚上给妈妈打电话</span></div>
<div style="margin-top:10px" class="note">进度 <span class="prog" style="width:150px"><span style="width:33%"></span></span>
  <b style="color:var(--h1)">1 / 3</b></div>
<h2>今日复盘</h2>
<div class="note">- 做成了：<br>- 卡住了：</div>
`

/* ───────────────────────── 二、待办 ───────────────────────── */

const todoEditor = `
<div><span class="k"># 看板 2026-W38</span></div>
<div>&nbsp;</div>
<div><span class="k">## 待办</span></div>
<div class="mark" data-tag="D2 行内控件：勾选 / 截止日 / 标签">
  <span class="ctl"><span class="box"></span> 文献综述
    <span class="due">📅 09-22</span><span class="tag">#论文</span></span><br>
  <span class="ctl"><span class="box"></span> 实验数据整理
    <span class="due">📅 09-20</span><span class="tag">#实验</span></span>
</div>
<div>&nbsp;</div>
<div><span class="k">## 进行中</span></div>
<div><span class="ctl"><span class="box"></span> 开题报告提纲 <span class="tag">#论文</span></span></div>
<div>&nbsp;</div>
<div><span class="k">## 已完成</span></div>
<div><span class="ctl"><span class="box on"></span> 文献检索 <span class="tag">#论文</span></span></div>
<div>&nbsp;</div>
<div class="ctl">进度 :: <span class="prog" style="width:120px"><span style="width:20%"></span></span>
  <span class="m">1/5（自动统计勾选项）</span></div>
<div>&nbsp;</div>
<div><span class="m">/* 语法兼容 Obsidian Tasks：@due(2026-09-22) #论文</span></div>
<div><span class="m">   其它编辑器里就是普通任务行，照常能读 */</span></div>
`

const todoPreview = `
<h1>看板 2026-W38</h1>
<div class="note">整体进度 <span class="prog" style="width:170px"><span style="width:20%"></span></span>
  <b style="color:var(--h1)">1 / 5</b></div>
<div class="kanban">
  <div class="col"><h3>待办 · 2</h3>
    <div class="card"><div class="t">☐ 文献综述</div>
      <div class="row"><span class="due">📅 09-22 · 剩 3 天</span><span class="tag">#论文</span></div></div>
    <div class="card"><div class="t">☐ 实验数据整理</div>
      <div class="row"><span class="due" style="border-color:var(--warn);color:var(--warn)">📅 09-20 · 剩 1 天</span>
        <span class="tag">#实验</span></div></div>
  </div>
  <div class="col"><h3>进行中 · 1</h3>
    <div class="card"><div class="t">☐ 开题报告提纲</div>
      <div class="row"><span class="tag">#论文</span></div></div>
  </div>
  <div class="col"><h3>已完成 · 1</h3>
    <div class="card"><div class="t done">☑ 文献检索</div>
      <div class="row"><span class="tag">#论文</span></div></div>
  </div>
</div>
<div class="note">看板列 = 「##」小标题；勾选即完成，卡片墙的待办筛选自动同步。</div>
`

/* ───────────────────────── 三、课堂笔记 ───────────────────────── */

const classEditor = `
<div><span class="k"># 线代 · 第 4 讲 · 特征值与相似对角化</span></div>
<div class="meta mark" data-tag="D1 元数据卡">
  <span class="label">属性</span>
  <span class="chip accent">📚 线性代数</span>
  <span class="chip">👤 王老师</span>
  <span class="chip">📅 2026-09-19</span>
</div>
<div class="mark" data-tag="D3 块容器">
  <div class="block">
    <div class="head">::: cornell 线代·第4讲</div>
    线索 :: 特征多项式 / 相似对角化 / 迹<br>
    笔记 :: det(A-λI)=0 求特征值；三条性质…<br>
    总结 :: 先求 λ，再求特征向量，最后验算迹<br>
    <span class="m">:::</span>
  </div>
</div>
<div>&nbsp;</div>
<div><span class="k">$$ T = 2\\pi\\sqrt{L/g} $$</span></div>
<div>&nbsp;</div>
<div class="block">
  <div class="head">::: data 单摆测 g</div>
  | 次数 | L(m) | T(s) |<br>| --- | --- | --- |<br>| 1 | 0.80 | 1.79 |<br>
  <span class="m">:::</span>
</div>
<div>&nbsp;</div>
<div class="ctl"><span class="box"></span> 红黑树旋转还是没懂
  <span class="m">← 勾选即加入待办</span></div>
`

const classPreview = `
<div class="props">
  <span class="pchip"><b>课程</b> 线性代数</span>
  <span class="pchip"><b>讲师</b> 王老师</span>
  <span class="pchip"><b>日期</b> 2026-09-19</span>
</div>
<h1>线代 · 第 4 讲 · 特征值与相似对角化</h1>
<div class="cornell">
  <div class="cell"><b>线索</b>特征多项式<br>相似对角化<br>迹与行列式</div>
  <div class="cell"><b>笔记</b>det(A-λI)=0 求特征值；<br>三条性质（迹=特征值之和）…</div>
  <div class="cell"><b>总结</b>先求 λ，再求特征向量，<br>最后验算迹</div>
</div>
<div style="margin-top:14px;font-family:var(--display);font-size:15px;color:var(--h2)">
  T = 2π√(L / g)</div>
<table><tr><th>次数</th><th>L(m)</th><th>T(s)</th></tr>
  <tr><td>1</td><td>0.80</td><td>1.79</td></tr>
  <tr><td>2</td><td>1.00</td><td>2.01</td></tr></table>
<div class="todo" style="margin-top:12px"><span class="box"></span>
  <span>红黑树旋转还是没懂 <span class="tag">→ 已加入待办</span></span></div>
`

/* ───────────────────────── 渲染 ───────────────────────── */

const SHOTS = [
  ['prototype-journal.png', '日记（D1 元数据卡 + D2 行内控件）：左边是编辑时的控件，右边是预览效果',
    'journal', [['日记 · 2026-09-19', 'journal'], ['待办', 'todo'], ['线代 · 第4讲', 'class']],
    journalEditor, journalPreview],
  ['prototype-todo.png', '待办（D2 控件 + 看板预览）：@due / #标签 点一下就能改，进度自动统计',
    'todo', [['待办', 'todo'], ['日记 · 2026-09-19', 'journal'], ['线代 · 第4讲', 'class']],
    todoEditor, todoPreview],
  ['prototype-class.png', '课堂笔记（D3 块容器）：康奈尔三栏 + 公式 + 数据表，疑问可直接变待办',
    'class', [['线代 · 第4讲', 'class'], ['日记 · 2026-09-19', 'journal'], ['待办', 'todo']],
    classEditor, classPreview],
]

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 1500, height: 900 }, deviceScaleFactor: 2 })
mkdirSync(OUT_DIR, { recursive: true })

for (const [file, caption, active, tabs, editorHTML, previewHTML] of SHOTS) {
  const html = `<!doctype html><html><head><meta charset="utf-8"><style>${CSS}</style></head>
    <body><div class="cap">${caption}</div>
    <div class="clear">样式取自「雾青」主题的真实配色与字体（--accent #1FA084 · --bg #FAFCF9 · 标题 #17735F）</div>
    ${windowShell(active, tabs, editorHTML, previewHTML)}</body></html>`
  await page.setContent(html, { waitUntil: 'load' })
  await page.waitForTimeout(250)
  await page.screenshot({ path: join(OUT_DIR, file), fullPage: true })
  console.log('已生成：', join(OUT_DIR, file))
}
await browser.close()
