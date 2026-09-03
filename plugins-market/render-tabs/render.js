// 渲染插件：:::tabs / :::tab 容器 → 标签页（before 钩子：md 文本级替换）
// 用法：
//   :::tabs
//   :::tab 概览
//   内容…
//   :::tab 详情
//   内容…
//   :::
//   :::
window.__registerRenderPlugin({
  id: 'render-tabs',
  before: function (md) {
    if (typeof md !== 'string') return md || '';

    function esc(s) {
      return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;');
    }
    function inline(s) {
      s = esc(s);
      s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
      s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
      s = s.replace(/\*([^*]+)\*/g, '<em>$1</em>');
      s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2" target="_blank" rel="noopener">$1</a>');
      s = s.replace(/~~([^~]+)~~/g, '<del>$1</del>');
      s = s.replace(/(^|\s)(https?:\/\/\S+)/g, '$1<a href="$2" target="_blank" rel="noopener">$2</a>');
      return s;
    }
    function blockHtml(text) {
      var blocks = String(text).split(/\n{2,}/);
      var out = [];
      for (var b = 0; b < blocks.length; b++) {
        var lines = blocks[b].split(/\r?\n/).map(function (l) { return inline(l).trim(); }).filter(Boolean);
        if (lines.length) out.push('<p>' + lines.join('<br>') + '</p>');
      }
      return out.join('');
    }
    function renderTabs(tabs) {
      var n = tabs.length;
      if (!n) return '';
      var html = '<div class="md-tabs"><div class="md-tabs-nav">';
      for (var a = 0; a < n; a++) {
        var nm = (tabs[a].name || '').trim() || ('标签' + (a + 1));
        html += '<button class="md-tab-label' + (a === 0 ? ' is-active' : '') + '" data-tab="' + a + '" type="button">' + esc(nm) + '</button>';
      }
      html += '</div><div class="md-tabs-body">';
      for (var b = 0; b < n; b++) {
        html += '<div class="md-tab-panel' + (b === 0 ? ' is-active' : '') + '" data-panel="' + b + '">'
          + blockHtml(tabs[b].content.join('\n')) + '</div>';
      }
      html += '</div></div>';
      return html;
    }

    var lines = md.split(/\r?\n/);
    var out = [];
    var i = 0;
    while (i < lines.length) {
      if (/^:::\s*tabs\s*$/.test(lines[i])) {
        var blockStart = i;
        i++;
        var tabs = [];
        var cur = null;
        while (i < lines.length) {
          var l = lines[i];
          var tabOpen = /^:::\s*tab\b\s*(.*)$/.exec(l);
          if (tabOpen) {
            if (cur) tabs.push(cur);
            cur = { name: (tabOpen[1] || '').trim(), content: [] };
            i++;
          } else if (/^:::\s*$/.test(l)) {
            if (cur) { tabs.push(cur); cur = null; i++; }
            else { break; }
          } else {
            if (cur) cur.content.push(l);
            i++;
          }
        }
        if (i < lines.length && /^:::\s*$/.test(lines[i])) i++;
        // 没有任何 :::tab 子块时原样保留，避免丢内容
        if (tabs.length === 0) {
          for (var fb = blockStart; fb < i; fb++) out.push(lines[fb]);
        } else {
          out.push(renderTabs(tabs));
        }
      } else {
        out.push(lines[i]);
        i++;
      }
    }
    return out.join('\n');
  },
  css: '.md-tabs{margin:1em 0;}'
    + '.md-tabs-nav{display:flex;flex-wrap:wrap;gap:4px;border-bottom:2px solid var(--border-strong);}'
    + '.md-tab-label{appearance:none;-webkit-appearance:none;border:1px solid transparent;border-bottom:none;background:transparent;color:var(--muted);padding:8px 14px;border-radius:8px 8px 0 0;cursor:pointer;font-size:0.95em;font-family:inherit;}'
    + '.md-tab-label:hover{color:var(--text);}'
    + '.md-tab-label.is-active{color:var(--accent);border-color:var(--border-strong);background:var(--code-bg);}'
    + '.md-tabs-body{border:1px solid var(--border-strong);border-top:none;border-radius:0 0 8px 8px;background:var(--code-bg);padding:12px;}'
    + '.md-tab-panel{display:none;}'
    + '.md-tab-panel.is-active{display:block;}'
    + '.md-tab-panel p{margin:0 0 8px;}'
});