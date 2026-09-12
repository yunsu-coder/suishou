// MarkNote 预览渲染管线 —— 移植自 start 项目 notes-panel.js 的 md2html 逻辑，
// 全部依赖本地 vendor/，离线可用。
(function () {
  // ===== 渲染扩展开关（轻量化：非必要语法可按需关闭；缺省全开）=====
  // Swift 侧在 renderMd/renderCode 前注入 window.__enabledModules = {...}
  function isMod(name) {
    var m = window.__enabledModules || {};
    return m[name] !== false;
  }

  // ===== 渲染插件（P3）：用户 markdown-it 插件 / 前后钩子 / CSS（Web 沙箱）=====
  var __renderExt = {
    use: [], before: [], after: [], css: []
  };
  window.__registerRenderPlugin = function (p) {
    p = p || {};
    if (typeof p.use === 'function') { __renderExt.use.push(p.use); }
    if (typeof p.before === 'function') { __renderExt.before.push(p.before); }
    if (typeof p.after === 'function') { __renderExt.after.push(p.after); }
    if (typeof p.css === 'string' && p.css) { __renderExt.css.push(p.css); }
  };
  function __applyRenderPlugins() {
    while (__renderExt.use.length) {
      try { mdRenderer.use(__renderExt.use.shift()); } catch (e) {}
    }
    while (__renderExt.css.length) {
      var css = __renderExt.css.shift();
      var st = document.createElement('style');
      st.textContent = css;
      document.head.appendChild(st);
    }
  }
  function __beforeRender(md) {
    for (var i = 0; i < __renderExt.before.length; i++) {
      try { md = __renderExt.before[i](md) || md; } catch (e) {}
    }
    return md;
  }
  function __afterRender(html) {
    for (var i = 0; i < __renderExt.after.length; i++) {
      try { html = __renderExt.after[i](html) || html; } catch (e) {}
    }
    return html;
  }

  'use strict';
  window.__jsError = null;
  window.addEventListener('error', function (e) { window.__jsError = String(e.message || e) + ' | ' + String(e.filename || '') + ':' + String(e.lineno || ''); });

  if (typeof markdownit === 'undefined') return;

  // ===== markdown-it 渲染器（单例）=====
  // hljs 渲染缓存（LRU，上限 600 块）：打字时未变化的代码块不重新高亮
  var hljsCache = {};
  var HLJS_MAX = 600;
  function hljsKey(lang, str) { return (lang || '') + '\u0000' + str; }
  function hljsRender(str, lang) {
    if (typeof hljs === 'undefined') return '';
    var key = hljsKey(lang, str);
    var hit = hljsCache[key];
    if (hit !== undefined) return hit;
    var out;
    try {
      if (lang && hljs.getLanguage(lang)) {
        out = hljs.highlight(str, { language: lang, ignoreIllegals: true }).value;
      } else {
        out = hljs.highlightAuto(str).value;
      }
    } catch (e) {
      out = '';
    }
    hljsCache[key] = out;
    var keys = Object.keys(hljsCache);
    if (keys.length > HLJS_MAX) {
      for (var i = 0; i < keys.length - HLJS_MAX + 300; i++) delete hljsCache[keys[i]];
    }
    return out;
  }

  var mdRenderer = markdownit({
    html: true, linkify: true, typographer: true, breaks: true,
    highlight: hljsRender,
  });

  if (isMod('emoji') && typeof markdownitEmoji !== 'undefined') mdRenderer.use(markdownitEmoji);
  if (isMod('footnote') && typeof markdownitFootnote !== 'undefined') mdRenderer.use(markdownitFootnote);
  if (isMod('sub') && typeof markdownitSub !== 'undefined') mdRenderer.use(markdownitSub);
  if (isMod('sup') && typeof markdownitSup !== 'undefined') mdRenderer.use(markdownitSup);
  if (isMod('mark') && typeof markdownitMark !== 'undefined') mdRenderer.use(markdownitMark);
  if (isMod('ins') && typeof markdownitIns !== 'undefined') mdRenderer.use(markdownitIns);
  if (isMod('tasklist') && typeof markdownitTaskLists !== 'undefined') mdRenderer.use(markdownitTaskLists, { enabled: true });

  var CALLOUT_LABELS = { note: '📝 笔记', warning: '⚠️ 警告', tip: '💡 提示', danger: '🔥 注意', info: 'ℹ️ 信息', details: '📋 详情' };
var CALLOUT_LABELS_EN = { note: '📝 Note', warning: '⚠️ Warning', tip: '💡 Tip', danger: '🔥 Danger', info: 'ℹ️ Info', details: '📋 Details' };
var __isEN = (window.__appLang === 'en');
  // 块级（类型后换行，直到独立 ::: 行）
  // 结束行只吃到行尾（不能吞后续空行）：否则紧随其后的 Markdown 会被当作 HTML block 原样输出。
  var CALLOUT_RE = /^:::[ \t]*(note|warning|tip|danger|info|details)[ \t]*\r?\n([\s\S]*?)^:::[ \t]*\r?$/gm;
  // 紧凑行内：:::warning 内容:::（或 :::warning:::）。仅限单行（内容可含任意字符含冒号）：
  // 永不跨行吞内容；行内最近一对 ::: 即边界。优先于 emoji 简码 —— 预处理先吞掉，
  // markdown-it-emoji 的 :warning: 只会在没有 ::: 结构时生效。
  var CALLOUT_INLINE_RE = /:::\s*(note|warning|tip|danger|info|details)(?:[ \t]+\s*([^\n]*?))?\s*:::/g;

  function preprocessCallouts(md) {
    var labels = __isEN ? CALLOUT_LABELS_EN : CALLOUT_LABELS;
    md = md.replace(CALLOUT_RE, function (_, type, content) {
      var label = labels[type] || type;
      var inner = mdRenderer.render(content.trim());
      return '<div class="callout callout-' + type + '">' +
             '<div class="callout-title">' + label + '</div>' +
             '<div class="callout-body">' + inner + '</div></div>\n\n';
    });
    md = md.replace(CALLOUT_INLINE_RE, function (m, type, content) {
      var label = labels[type] || type;
      var inner = content ? mdRenderer.render(content.trim()) : '';
      return '<div class="callout callout-' + type + '">' +
             '<div class="callout-title">' + label + '</div>' +
             '<div class="callout-body">' + inner + '</div></div>';
    });
    return md;
  }

  // ===== 附件卡片（知乎风格）：[名字](attachments/…) → 文件卡片；点击直接打开 =====
  var EXT_KIND = [
    ['pdf', 'pdf'], ['doc', 'word'], ['docx', 'word'], ['ppt', 'ppt'], ['pptx', 'ppt'],
    ['xls', 'sheet'], ['xlsx', 'sheet'], ['csv', 'sheet'], ['txt', 'text'], ['md', 'text'],
    ['zip', 'zip'], ['rar', 'zip'], ['7z', 'zip'], ['tar', 'zip'], ['gz', 'zip'],
    ['png', 'image'], ['jpg', 'image'], ['jpeg', 'image'], ['gif', 'image'], ['webp', 'image'],
    ['mov', 'video'], ['mp4', 'video'], ['m4a', 'video'], ['mv4', 'video'],
    ['mkv', 'video'], ['webm', 'video'], ['avi', 'video'],
    ['mp3', 'audio'], ['wav', 'audio'], ['flac', 'audio'], ['other', 'other'],
  ];
  function attachType(ext) {
    var e = String(ext || '').toLowerCase();
    for (var i = 0; i < EXT_KIND.length; i++) if (EXT_KIND[i][0] === e) return EXT_KIND[i][1];
    return 'other';
  }
  var ATTACH_LABELS = { pdf: 'PDF 文档', word: 'Word 文档', ppt: '演示文稿', sheet: '表格',
             text: '文本文件', zip: '压缩包', image: '图片', video: '视频', audio: '音频',
             other: '文件' };
  var ATTACH_LABELS_EN = { pdf: 'PDF Document', word: 'Word Document', ppt: 'Presentation', sheet: 'Spreadsheet',
             text: 'Text File', zip: 'Archive', image: 'Image', video: 'Video', audio: 'Audio',
             other: 'File' };
  function attachLabel(kind) {
    return (__isEN ? ATTACH_LABELS_EN : ATTACH_LABELS)[kind] || (__isEN ? 'File' : '文件');
  }
  function escHtml(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }
  function attachmentCard(name, href) {
    var kind = attachType(name.split('.').pop());
    var label = attachLabel(kind);
    var iconText = name.split('.').pop().slice(0, 3).toUpperCase();
    // href 做 URI 编码（文件名可能含空格/中文 → HTML 属性与点击取回均安全）
    var encHref = escapeURI(href);
    return '<a class="attach-card" href="' + encHref + '" ' +
           'data-kind="' + kind + '" ' + (__isEN ? 'title="Click to open"' : 'title="点击打开"') + '>' +
           '<span class="attach-icon attach-' + kind + '">' + escHtml(iconText) + '</span>' +
           '<span class="attach-meta">' +
           '<span class="attach-name">' + escHtml(name) + '</span>' +
           '<span class="attach-type">' + label + (__isEN ? ' · Click to open</span>' : ' · 点击打开</span>') +
           '</span></a>';
  }
  function escapeURI(href) {
    try { return encodeURI(href); } catch (e) { return href; }
  }
  // 用 encodeURI 处理空格/中文，卡片内展示原文件名
  // ① 未渲染前的 markdown 源：[]() 形式（markdown-it 常因空格拒绝 URL → 这里直接接管）
  function preprocessAttachments(md) {
    // 语义前缀 @：@[名](路径) = 附件卡（任意类型、不看扩展名；与普通 [名](路径) 链接明确区分）
    md = md.replace(/@\[([^\]]+)\]\(([^)\n]+?)(?:\s+"[^"]*")?\)/g, function (_, name, href) {
      return attachmentCard(String(name).replace(/\s+/g, ' '), href);
    });
    // 兼容旧 attachments/ 路径（历史数据）
    md = md.replace(/\[([^\]]+)\]\((attachments\/[^)\n]+?)(?:\s+"[^"]*")?\)/g, function (_, name, href) {
      return attachmentCard(String(name).replace(/\s+/g, ' '), href);
    });
    return md;
  }
  // ② markdown-it 已渲染的 <a href="attachments/…">名字</a>（空格少的文件名）
  function decorAttachments(html) {
    return html.replace(/<a[^>]*href="(attachments\/[^"]+)"[^>]*>([^<]*)<\/a>/g, function (_, href, name) {
      return attachmentCard(name, href);
    });
  }

  function md2html(md) {
    if (!md) return '<p></p>';
    md = __beforeRender(md);
    try {
      // 0. 代码保护：围栏/行内代码先占位，避免内部 @[] / ::: / $...$ 被扩展语法误吞。
      var rawCode = [];
      md = md.replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[ \t]*$/gm, function (m) {
        rawCode.push(m);
        return '\u0000RAWCODE' + (rawCode.length - 1) + '\u0000';
      });
      md = md.replace(/`[^`\n]+`/g, function (m) {
        rawCode.push(m);
        return '\u0000RAWCODE' + (rawCode.length - 1) + '\u0000';
      });
      function restoreRawCode(s) {
        return s.replace(/\u0000RAWCODE(\d+)\u0000/g, function (_, i) {
          return rawCode[Number(i)] || '';
        });
      }
      // 0. 附件卡片预处理（先于 markdown-it：接管带空格/中文的附件链接）
      if (isMod('attachments')) { md = preprocessAttachments(md); }
      // 0.5 多级编号行（`1.1 内容` / `1.1.1 内容` …）：标准 Markdown 不认这种编号，默认会被
      //     吸进上一个列表项；这里转成按层级缩进的独立行块，编号原样保留（手写章节编号的读感）
      md = md.replace(/^([ \t]*)(\d+(?:\.\d+)+\.?)[ \t]+(.*\S)[ \t]*$/gm, function (m, ws, num, text) {
        var depth = Math.min(num.split('.').length - 1, 4);
        return '<div class="num-line num-depth-' + depth + '">' + escHtml(num) + ' ' + escHtml(text) + '</div>';
      });
      // 1. 提取脚注定义（HTML block 后的定义 markdown-it 不识别，先挪走）
      var footnoteDefs = '';
      var mdClean = isMod('footnote') ? md.replace(/^\[\^[^\]]+\]:\s*.+(\n\s{2,}.+)*/gm, function (m) {
        footnoteDefs += (footnoteDefs ? '\n' : '') + m.trim();
        return '';
      }) : md;
      // 2. callout 预处理
      var processed = isMod('callout') ? preprocessCallouts(mdClean) : mdClean;
      // 3. 脚注定义插到第一个 callout HTML 之前
      if (footnoteDefs) {
        var i = processed.indexOf('<div class="callout');
        processed = i > -1 ? processed.slice(0, i) + footnoteDefs + '\n\n' + processed.slice(i)
                           : processed + '\n\n' + footnoteDefs;
      }
      processed = restoreRawCode(processed);
      // 4. 主渲染
      var h = mdRenderer.render(processed);
      // 5. 渲染后的附件 <a> 统一装饰为卡片
      if (isMod('attachments')) { h = decorAttachments(h); }
      h = h.replace(/<img /g, '<img loading="lazy" ');
      h = h.replace(/<a /g, '<a target="_blank" rel="noopener" ');
      h = h.replace(/<pre><code class="language-(\w+)">/g, '<pre data-lang="$1"><code class="language-$1">');
      // 5. KaTeX（$$ 块级 / $ 行内）
      var codeFragments = [];
      h = h.replace(/<(pre|code)\b[^>]*>[\s\S]*?<\/\1>/g, function (m) {
        codeFragments.push(m);
        return '\u0000CODEFRAG' + (codeFragments.length - 1) + '\u0000';
      });
      
  // ===== KaTeX 渲染缓存（LRU 500）：公式多时避免每帧重算 =====
  var katexCache = {}, KATEX_MAX = 500;
  function renderKaTeX(tex, display) {
    var key = (display ? 'd|' : 'i|') + tex;
    var hit = katexCache[key];
    if (hit !== undefined) return hit;
    var out;
    try {
      out = katex.renderToString(tex.trim(), { displayMode: display, throwOnError: false });
    } catch (e) {
      out = display ? ('<div>' + tex + '</div>') : ('<span>' + tex + '</span>');
    }
    katexCache[key] = out;
    var ks = Object.keys(katexCache);
    if (ks.length > KATEX_MAX) { for (var i = 0; i < ks.length - KATEX_MAX + 100; i++) delete katexCache[ks[i]]; }
    return out;
  }

if (typeof katex !== 'undefined') {
        try {
          h = h.replace(/\$\$([\s\S]*?)\$\$/g, function (m, f) {
            try { return renderKaTeX(f.trim(), true); } catch (e) { return m; }
          });
          // 行内公式：不跨行、首尾不留空格；避免货币等成对 $ 被误判。
          h = h.replace(/\$(?!\s)([^\$\n]*[^\s\$])\$(?!\$)/g, function (m, f) {
            try { return renderKaTeX(f.trim(), false); } catch (e) { return m; }
          });
        } catch (e) {}
      }
      h = h.replace(/\u0000CODEFRAG(\d+)\u0000/g, function (_, i) {
        return codeFragments[Number(i)] || '';
      });
      // 5.9 图片卡片属性语法（宽高/图注一体）
      h = applyImageAttrs(h);
      return __afterRender(h) || '<p></p>';
    } catch (e) {
      console.warn('[preview] render error', e);
      return '<p>' + String(md).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>') + '</p>';
    }
  }
  // ===== 图片相对路径 → file://（相对笔记目录）=====

  // ===== 图片注册表：Swift 侧按版本增量下发（path → dataURL），条目不随每帧渲染重复桥接 =====
  var IMG_REG = {};
  window.__setEntry = function (path, dataURL) { IMG_REG[path] = dataURL; window.__imgRegCount = Object.keys(IMG_REG).length; };

  // ===== 自定义字体：Swift 侧下发 data URL → 注入 @font-face ===
  //（WebContent 进程读不到宿主 CTFontManager 注册的字体，字体字节必须进页面）
  var FONT_ALIAS = {};
  window.__setFont = function (family, dataURL) {
    if (FONT_ALIAS[family]) return;
    FONT_ALIAS[family] = true;
    window.__fontCount = Object.keys(FONT_ALIAS).length;
    var safe = String(family).replace(/["'\\]/g, '');
    var style = document.createElement('style');
    style.textContent = '@font-face { font-family: "' + safe + '"; src: url("' + dataURL + '"); }';
    document.head.appendChild(style);
  };

  function resolveImages(html, baseDir) {
    return html.replace(/(<img[^>]*src=")([^"]+)(")/g, function (m, pre, src, post) {
      if (/^(https?:|data:|file:)/.test(src)) return m;
      var key = src.replace(/^\.?\//, '');
      // 插入时对空格/括号做了百分号编码 → 解回来再查注册表（双键查找，原样键优先）
      var keyDecoded = key;
      try { keyDecoded = decodeURIComponent(key); } catch (e) {}
      if (IMG_REG[key]) { return pre + IMG_REG[key] + post; }   // 注册表命中：data URL 直出
      if (IMG_REG[keyDecoded]) { return pre + IMG_REG[keyDecoded] + post; }
      if (baseDir) return pre + baseDir + key + post;
      return m;
    });
  }

  // ===== 图片卡片语法：![alt](src){width=300 / width=60% / height=200 / caption=图注} =====
  // 属性组一次性解析（逗号分隔）；有 caption 时包 figure.img-card + figcaption
  function withStyleRaw(img, style) {
    var nm = /style="([^"]*)"/.exec(img);
    if (nm !== null) { return img.replace(/style="[^"]*"/, 'style="' + nm[1] + ';' + style + '"'); }
    return img.replace('<img', '<img style="' + style + '"');
  }
  function applyImageAttrs(html) {
    return html.replace(/(<img[^>]*>)\s*\{\s*([^}]+?)\s*\}/g, function (m, img, attrs) {
      var style = '', cap = '';
      attrs.split(',').forEach(function (kv) {
        var eq = kv.indexOf('=');
        if (eq < 0) { return; }
        var k = kv.slice(0, eq).trim().toLowerCase();
        var v = kv.slice(eq + 1).trim();
        if (k === 'width' || k === 'height') {
          var num = v.replace(/[^\d.]/g, '');
          style += k + ':' + (num || v) + (v.indexOf('%') >= 0 ? '%' : 'px') + ';';
        } else if (k === 'caption') {
          cap = v.replace(/^"|"$/g, '');
        }
      });
      if (style) { img = withStyleRaw(img, style); }
      if (cap) {
        return '<figure class="img-card">' + img.replace('<img', '<img class="card-img"') +
               '<figcaption>' + cap.replace(/</g, '&lt;') + '</figcaption></figure>';
      }
      return img;
    });
  }

  // ===== 锚点宽松匹配：手写 [xx](#yy) 链接与 GitHub 式 slug 差异时仍可跳转 =====
  function findHeadingByAnchor(id) {
    if (!id) { return null; }
    var heads = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
    var norm = function (t) {
      return String(t).toLowerCase().replace(/\s+/g, '').replace(/[-_]/g, '').replace(/[^\p{L}\p{N}]/gu, '');
    };
    var target = norm(id);
    if (!target) { return null; }
    // 1) 已有 id（anchorize 生成的 slug）归一化比较
    for (var i = 0; i < heads.length; i++) {
      if (heads[i].id && norm(heads[i].id) === target) { return heads[i]; }
    }
    // 2) 标题文本归一化包含匹配（支持「#功能特性 说明」这类手写）
    for (var j = 0; j < heads.length; j++) {
      var t = norm(heads[j].textContent);
      if (t.indexOf(target) !== -1) { return heads[j]; }
    }
    return null;
  }

  // ===== 标题锚点（slug 化 + 同名序号）+ [TOC] 目录占位符 =====
  var anchorSeen = {};
  function slugify(text) {
    var t = String(text || '').replace(/<[^>]+>/g, '').toLowerCase().trim();
    t = t.replace(/[^\p{L}\p{N}\s-]/gu, '').replace(/\s+/g, '-');
    if (!t) { t = 'section'; }
    var n = anchorSeen[t] || 0;
    anchorSeen[t] = n + 1;
    return n === 0 ? t : t + '-' + n;
  }
  function anchorize(html) {
    anchorSeen = {};
    return html.replace(/<h([1-4])([^>]*)>(.*?)<\/h\1>/g, function (m, level, attrs, inner) {
      var id = slugify(inner);
      return '<h' + level + ' id="' + id + '" class="anchored"><a class="anchor" href="#' + id + '">#</a>' + inner + '</h' + level + '>';
    });
  }
  function buildTOC(anchoredHtml) {
    var items = [];
    var re = /<h([1-4])\s+id="([^"]+)"[^>]*>(.*?)<\/h\1>/g, m;
    while ((m = re.exec(anchoredHtml)) !== null) {
      var text = m[3].replace(/<a class="anchor"[^>]*>.*?<\/a>/g, '').replace(/<[^>]+>/g, '');
      items.push('<li class="toc-level-' + m[1] + '"><a href="#' + m[2] + '">' + text + '</a></li>');
    }
    if (!items.length) { return ''; }
    return '<nav class="toc"><ul>' + items.join('') + '</ul></nav>';
  }

  // ===== mermaid 懒加载 =====
  var mermaidReady = null;
  function ensureMermaid() {
    if (!mermaidReady) {
      mermaidReady = new Promise(function (resolve, reject) {
        var s = document.createElement('script');
        s.src = 'vendor/mermaid.min.js';
        s.onload = resolve;
        s.onerror = function () { mermaidReady = null; reject(new Error('mermaid 加载失败')); };
        document.head.appendChild(s);
      });
    }
    return mermaidReady;
  }

  // mermaid 渲染缓存（相同源码+主题直接复用 SVG，上限 100 张图）
  var mermaidCache = {};
  var MERMAID_MAX = 100;
  function mermaidKey(code, dark) { return (dark ? 'd|' : 'l|') + code; }

  function applyMermaidResult(pre, el, svg, id) {
    var div = document.createElement('div');
    div.className = 'mermaid-rendered';
    div.id = id;
    div.innerHTML = svg;
    if (pre) pre.replaceWith(div);
  }

  // ===== Mermaid 容错：mindmap 缺根 → 自动补 root (mermaid v11 强制根语法) =====
  function normalizeMermaid(code) {
    var trimmed = String(code || '').trim();
    if (!/^mindmap\b/i.test(trimmed)) return trimmed;
    var seg = trimmed.split('\n');
    // 1) 缺根 → 补根，且首个节点强制缩进（mermaid 仅允许一个 root）
    var hasRoot = false;
    for (var i = 1; i < seg.length; i++) {
      var t = seg[i].trim();
      if (!t) continue;
      if (/^root\b/i.test(t) || /^\(/.test(t)) { hasRoot = true; }
      break;
    }
    if (!hasRoot) {
      for (var i = 1; i < seg.length; i++) {
        if (seg[i].trim()) {
          seg.splice(i, 0, 'root((思维导图))');
          seg[i + 1] = '  ' + seg[i + 1].trim();
          break;
        }
      }
    }
    // 2) 其余零缩进节点统一挑 2 空格挂到根下（还原层级，避免"只能有一个 root"）
    for (var j = 1; j < seg.length; j++) {
      var tt = seg[j].trim();
      if (!tt) continue;
      var ind = seg[j].length - seg[j].replace(/^\s+/, '').length;
      if (ind === 0 && !/^root\b/i.test(tt) && !/^\(/.test(tt)) {
        seg[j] = '  ' + seg[j].trim();
      }
    }
    return seg.join('\n');
  }

  function renderMermaid(container, dark) {
    var blocks = container.querySelectorAll('pre code.language-mermaid');
    if (!blocks.length) return;
    // 命中的立即替换；未命中的等 mermaid 加载后渲染
    var pending = [];
    blocks.forEach(function (el) {
      var text = normalizeMermaid(el.textContent);
      var key = mermaidKey(text, dark);
      var cached = mermaidCache[key];
      var pre = el.closest('pre');
      if (cached !== undefined) {
        applyMermaidResult(pre, el, cached, null);
      } else {
        pending.push({ el: el, pre: pre, key: key });
      }
    });
    if (!pending.length) return;
    ensureMermaid().then(function () {
      try {
        mermaid.initialize({ startOnLoad: false, theme: dark ? 'dark' : 'default', securityLevel: 'loose' });
      } catch (e) {}
      pending.forEach(function (p) {
        var id = 'm-' + Math.random().toString(36).slice(2, 8);
        try {
          mermaid.render(id, normalizeMermaid(p.el.textContent)).then(function (result) {
            mermaidCache[p.key] = result.svg;
            var keys = Object.keys(mermaidCache);
            if (keys.length > MERMAID_MAX) delete mermaidCache[keys[0]];
            applyMermaidResult(p.pre, p.el, result.svg, id);
          }).catch(function (err) {
            if (p.pre) p.pre.insertAdjacentHTML('afterend',
              '<div class="mermaid-error">⚠️ Mermaid: ' + String(err.message || err).replace(/</g, '&lt;') + '</div>');
          });
        } catch (e) {
          if (p.pre) p.pre.insertAdjacentHTML('afterend',
            '<div class="mermaid-error">⚠️ Mermaid: ' + String(e.message || e).replace(/</g, '&lt;') + '</div>');
        }
      });
    }).catch(function (err) {
      pending.forEach(function (p) {
        if (p.pre) p.pre.insertAdjacentHTML('afterend', '<div class="mermaid-error">⚠️ ' + err.message + '</div>');
      });
    });
  }

  // ===== 标题点击折叠 =====
  function applyFoldHint(container) {
    container.querySelectorAll('h1, h2, h3, h4').forEach(function (h) {
      if (h.dataset.foldInited) return;
      h.dataset.foldInited = '1';
      h.style.cursor = 'pointer';
      h.addEventListener('click', function () {
        var group = [];
        var el = h.nextElementSibling;
        while (el && el.tagName !== h.tagName && !/^H[1-6]$/.test(el.tagName)) {
          group.push(el);
          el = el.nextElementSibling;
        }
        var hidden = group.every(function (g) { return g.style.display === 'none'; });
        group.forEach(function (g) { g.style.display = hidden ? '' : 'none'; });
        h.classList.toggle('folded', !hidden);
      });
    });
  }

  // ===== 外部链接交给宿主（NSWorkspace.open）+ 图片点击查看大图 =====
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (a) {
      e.preventDefault();
      var href = a.getAttribute('href') || '';
      if (href.charAt(0) === '#') {
        // [TOC] / 标题锚点：文档内平滑跳转；手写锚点做宽松匹配兜底
        var aid = href.slice(1);
        var target = document.getElementById(aid);
        if (!target) { target = findHeadingByAnchor(aid); }
        if (target) { target.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
        return;
      }
      if (/^https?:/.test(href)) {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openURL) {
          window.webkit.messageHandlers.openURL.postMessage(href);
        } else {
          window.open(href, '_blank');
        }
      } else if (/^(attachments|images)\//.test(href)) {
        // 附件链接 → 宿主解析打开（相对路径原样送出）
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openFile) {
          window.webkit.messageHandlers.openFile.postMessage(href);
        }
      }
      return;
    }
    var img = e.target && e.target.closest ? e.target.closest('img') : null;
    if (img && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openImage) {
      e.preventDefault();
      // 内联图（data URL）/ 远程图：Swift 侧把原始路径写入 title="img:<path>"，
      // 点击回传原始路径由宿主解析原图（修复：data URL 直接回传被宿主拒绝，C-06）。
      // 无标记时回退 img src（file:// 绝对路径或 http(s) URL）。
      var marker = img.getAttribute('title') || '';
      var m = /^img:(.*)$/.exec(marker);
      var payload = m ? m[1].replace(/&amp;/g, '&').replace(/&quot;/g, '"') : (img.getAttribute('src') || '');
      window.webkit.messageHandlers.openImage.postMessage(payload);
    }
  });

  // ===== 点击分发：外链（openURL）/ 图片（openImage，标签载荷优先）/ 附件（openFile） =====
  document.addEventListener('click', function (e) {
    var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
    if (a) {
      e.preventDefault();
      var href = a.getAttribute('href') || '';
      var hasHandlers = window.webkit && window.webkit.messageHandlers;
      if (hasHandlers) {
        if (/^https?:/.test(href) && window.webkit.messageHandlers.openURL) {
          window.webkit.messageHandlers.openURL.postMessage(href);
        } else if (window.webkit.messageHandlers.openFile) {
          window.webkit.messageHandlers.openFile.postMessage(href);
        }
      }
      return;
    }
    var img = e.target && e.target.closest ? e.target.closest('img') : null;
    if (img && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.openImage) {
      // C-06：内联图的 title="img:<原始相对路径>" 保留原始引用 → 回传宿主
      var payload = img.getAttribute('title') || '';
      if (payload.indexOf('img:') === 0) payload = payload.slice(4);
      if (!payload) payload = img.getAttribute('src') || '';
      window.webkit.messageHandlers.openImage.postMessage(payload);
    }
  });

  // ===== 滚动跟随：光标所在标题（含同名出现序号）→ scrollIntoView =====
  window.scrollToHeading = function (t, occ) {
    var els = document.querySelectorAll('h1,h2,h3,h4,h5,h6');
    var count = 0;
    for (var i = 0; i < els.length; i++) {
      if (els[i].textContent.trim() === t) {
        if (count === occ) {
          els[i].scrollIntoView({ block: 'start', behavior: 'instant' });
          return true;
        }
        count++;
      }
    }
    return false;
  };

  
  // ===== 媒体渲染：视频 / 音频内嵌播放器；文档转可点击卡片（openFile 链路） =====
  function renderMedia(html) {
    function card(title, href) {
      return '<div class="attach-card" style="margin:.8em 0;"><a href="' + href + '" class="attach-link">📄 ' + title + '</a></div>';
    }
    // 旧写法兼容：![x](a.mp4) 由 markdown-it 渲染成 <img> → 这里换成内嵌播放器
    // （素材面板现在的规范写法直接产出 <video src controls>，不再依赖本兼容层）
    html = html.replace(/<img[^>]*src="([^"]+\.(?:mp4|mov|webm|m4v|mkv|avi|mv4))"[^>]*>/gi,
      function (m, src) { return '<video class="md-media" controls preload="metadata" src="' + src + '"></video>'; });
    html = html.replace(/<img[^>]*src="([^"]+\.(?:mp3|wav|m4a|aac|ogg|flac|aiff))"[^>]*>/gi,
      function (m, src) { return '<audio class="md-media" controls preload="metadata" src="' + src + '"></audio>'; });
    html = html.replace(/<img[^>]*src="([^"]+\.(?:pdf|docx?|xlsx?|pptx?|zip|txt))"[^>]*alt="([^"]*)"[^>]*>/gi,
      function (m, src, alt) { return card(alt || src.split('/').pop(), src); });
    // 手写 HTML 内嵌媒体：统一挂主题 class，样式全部交给 CSS（主题可随时换皮）
    html = html.replace(/<(video|audio)\b(?![^>]*\bclass=)/gi, '<$1 class="md-media"');
    return html;
  }

  // ===== 代码块：悬停复制（REQ-FT-02；语言角标由 CSS ::after 提供，导出亦保留）=====
  // 导出 HTML 不含本 JS（ExportService 不打包 preview.js）→ 导出件无复制按钮，符合「无 JS 不显示」验收
  function applyCodeBlocks(root) {
    var pres = root.querySelectorAll('pre');
    for (var i = 0; i < pres.length; i++) {
      var pre = pres[i];
      if (pre.querySelector('.code-card-head')) continue;
      // 代码卡片头：语言徽章 + 常驻复制按钮（hover 提亮）
      var head = document.createElement('div');
      head.className = 'code-card-head';
      var langSpan = document.createElement('span');
      langSpan.className = 'lang';
      langSpan.textContent = pre.getAttribute('data-lang') || 'code';
      head.appendChild(langSpan);
      var btn = document.createElement('button');
      btn.type = 'button';
      btn.className = 'copy-btn';
      btn.textContent = '复制';
      (function (target) {
        btn.addEventListener('click', function () { copyCode(target, btn); });
      })(pre);
      head.appendChild(btn);
      pre.insertBefore(head, pre.firstChild);
    }
  }

  function copyCode(pre, btn) {
    var code = pre.querySelector('code');
    var text = code ? (code.textContent || '') : '';
    var announce = function () {
      btn.textContent = '✓ 已复制';
      setTimeout(function () { btn.textContent = '复制'; }, 1200);
    };
    var fallback = function () {
      var ta = document.createElement('textarea');
      ta.value = text;
      ta.style.position = 'fixed'; ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(ta);
      announce();
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(announce, fallback);
    } else {
      fallback();
    }
  }

  // ===== 代码文件预览（VSCode 式：非 Markdown 文本 → 语法高亮只读视图）=====
  function escForCode(s) {
    return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
  window.renderCode = function (text, lang, opts) {
    var container = document.getElementById('content');
    opts = opts || {};
    var cls = (lang || 'plaintext').toLowerCase();
    var html = '';
    if (typeof hljs !== 'undefined' && lang && hljs.getLanguage(cls)) {
      try { html = hljs.highlight(text, { language: cls, ignoreIllegals: true }).value; }
      catch (e) { html = escForCode(text); }
    } else {
      html = escForCode(text);
    }
    var lines = text.split('\n').length;
    container.innerHTML =
      '<div class="codefile"><div class="codefile-head">' +
      '<span class="codefile-lang">' + escForCode(lang || 'text') + '</span>' +
      '<span class="codefile-lines">' + lines + ' 行</span>' +
      '</div><pre class="codefile-pre"><code class="language-' + cls + '">' + html + '</code></pre></div>';
    if (opts.resetScroll) { window.scrollTo(0, 0); }
    return container.scrollHeight;
  };

window.renderMd = function (md, baseDir, opts) {
    try {
    var t0 = performance ? performance.now() : Date.now();
    var container = document.getElementById('content');
    opts = opts || {};
    // 渲染扩展（内置 renders/*.js + 用户渲染插件）：注册 markdown-it 插件并注入它们的 CSS。
    // 必须在 md2html 之前调用 —— 否则 before/after 钩子生效、而 use 插件与 CSS 被静默丢弃。
    __applyRenderPlugins();
    // REQ-RN-03 滚动锚定：渲染前记录视口比例，重渲后按内容比例恢复（编辑时预览不跳顶）
    var scrollRatio = 0;
    var availBefore = document.documentElement.scrollHeight - window.innerHeight;
    if (availBefore > 0) { scrollRatio = window.pageYOffset / availBefore; }
    var html = renderMedia(resolveImages(md2html(md), baseDir || null));
    // 标题锚点（anchor）与 [TOC] 目录（toc）独立开关
    if (isMod('anchor') || isMod('toc')) {
      html = anchorize(html);
      if (isMod('toc') && html.indexOf('[TOC]') !== -1) {
        var tocHtml = buildTOC(html);
        if (tocHtml) {
          html = html.replace(/<p>\s*\[TOC\]\s*<\/p>/g, tocHtml);
        }
      }
    }
    container.innerHTML = html;
    // HTML 导出（exportMode 非 posterMode）：视频/音频「附件卡」转回内嵌播放器 ——
    // @[名](source/…mp4) 的卡在导出件里同样可播（src 由 Swift 侧内联 data URL）
    if (opts.exportMode && !opts.posterMode) {
      var cardEls = container.querySelectorAll('a.attach-card[data-kind="video"], a.attach-card[data-kind="audio"]');
      for (var ci = 0; ci < cardEls.length; ci++) {
        var ca = cardEls[ci];
        var chref = ca.getAttribute('href');
        if (!chref) { continue; }
        var isVid = ca.getAttribute('data-kind') === 'video';
        var me = document.createElement(isVid ? 'video' : 'audio');
        me.controls = true;
        me.setAttribute('src', chref);
        me.style.maxWidth = '100%';
        me.style.borderRadius = '10px';
        me.style.display = 'block';
        ca.replaceWith(me);
      }
    }
    // 媒体节点保留：重建 DOM 前记录现有 video/audio（按 src 键），重建后把同元素搬回 ——
    // 打字导致的预览刷新不再打断播放、不再闪烁（体验痛点根治）
    var mediaRefs = {};
    var mediaLive = container.querySelectorAll('video[src], audio[src]');
    for (var li = 0; li < mediaLive.length; li++) {
      var mv = mediaLive[li];
      mediaRefs[mv.getAttribute('src')] = mv;
    }
    // PDF 导出（posterMode）：视频/音频不可交互 → 静态附件卡（打印友好）
    //   HTML 导出不走这里 —— 保留播放器（swift 侧把 src 内联为 data URL，离线可播）
    if (opts.posterMode) {
      var els = container.querySelectorAll('video, audio');
      for (var ei = 0; ei < els.length; ei++) {
        var v = els[ei];
        var name = (v.getAttribute('data-name') || v.getAttribute('src') || '媒体').split('/').pop();
        var card = document.createElement('div');
        card.className = 'attach-card';
        card.textContent = '🎬 ' + decodeURIComponent(name);
        v.replaceWith(card);
      }
    } else if (!opts.exportMode) {
      // 预览模式：HTML 内嵌媒体（<video>/<audio> 及 source）相对 src → 工作台根 file://：
      // 页面位于 .preview/ 镜像，相对路径会错解析到镜像目录 → 按 baseDir（工作台根）重写
      var mediaEls = container.querySelectorAll('video[src], audio[src], video source[src], audio source[src]');
      for (var mi = 0; mi < mediaEls.length; mi++) {
        var el = mediaEls[mi];
        var src = el.getAttribute('src');
        if (src && !/^(https?:|data:|file:)/.test(src)) {
          el.setAttribute('src', (baseDir || '') + src.replace(/^\.?\//, ''));
          el.load && el.load();
        }
      }
    }
    // 同源媒体原节点搬家（播放进度/状态延续）；仅当 src 完全一致时替换
    var mediaNew = container.querySelectorAll('video[src], audio[src]');
    for (var mi2 = 0; mi2 < mediaNew.length; mi2++) {
      var nv = mediaNew[mi2];
      var key = nv.getAttribute('src');
      if (key && mediaRefs[key] && mediaRefs[key] !== nv) {
        nv.replaceWith(mediaRefs[key]);
      }
    }
    if (isMod('fold')) { applyFoldHint(container); }
    applyCodeBlocks(container);
    if (isMod('mermaid')) { renderMermaid(container, opts.dark); }
    if (opts.resetScroll) { window.scrollTo(0, 0); }
    else if (scrollRatio > 0) {
      var avail = document.documentElement.scrollHeight - window.innerHeight;
      window.scrollTo(0, scrollRatio * avail);
    }
    window.__lastRenderMs = Math.round((performance ? performance.now() : Date.now()) - t0);
    return container.scrollHeight;
    } catch (e) {
      window.__jsError = 'renderMd: ' + String((e && e.message) || e) + ' | ' + String((e && e.stack) || '').split('\n').slice(0, 3).join(' <= ');
      return -1;
    }
  };

  window.__ready = true;

  // ===== 双击正文空白 → 阅读专注态（交给宿主；不劫持链接 / 图片 / 代码 / 已选中文本上的双击）=====
  document.addEventListener('dblclick', function (e) {
    var mh = window.webkit && window.webkit.messageHandlers;
    if (!mh || !mh.readerFocus) return;
    var t = e.target;
    if (t && t.closest && t.closest('a, img, video, audio, pre, code, table, .attach-card, input, textarea, button')) return;
    var sel = window.getSelection ? String(window.getSelection()) : '';
    if (sel && sel.length > 0) return;   // 双击选词时不触发
    mh.readerFocus.postMessage('toggle');
  });
})();
