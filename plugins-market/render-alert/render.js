// 渲染插件：!!! 标题 → 告警横幅（before 钩子：md 文本级替换）
// 用法：
//   !!! warning 磁盘空间不足
//   请及时清理缓存，避免写入失败。
window.__registerRenderPlugin({
  id: 'render-alert',
  before: function (md) {
    if (typeof md !== 'string') return md || '';
    var SEV = {
      note: 'note', info: 'info', tip: 'info',
      warning: 'warning', warn: 'warning',
      danger: 'danger', error: 'danger', err: 'danger', fail: 'danger', failed: 'danger',
      success: 'success', ok: 'success', done: 'success'
    };
    var ICON = { note: '\uD83D\uDCA1', info: '\u2139\uFE0F', warning: '\u26A0\uFE0F', danger: '\u274C', success: '\u2705' };

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

    var lines = md.split(/\r?\n/);
    var out = [];
    var i = 0;
    while (i < lines.length) {
      var m = /^!!!\s*(.*)$/.exec(lines[i]);
      if (m) {
        var rest = (m[1] || '').trim();
        var sev = 'note';
        var title = rest;
        var tk = rest.split(/\s+/);
        var first = (tk[0] || '').toLowerCase();
        if (SEV[first]) { sev = SEV[first]; title = tk.slice(1).join(' '); }
        if (!title) title = '注意';
        i++;
        var body = [];
        while (i < lines.length) {
          if (/^!!!\s*$/.test(lines[i]) || /^!!!\s/.test(lines[i])) break;
          if (/^\s*$/.test(lines[i])) break;
          body.push(lines[i]);
          i++;
        }
        out.push('<div class="md-alert md-alert-' + sev + '"><div class="md-alert-title">'
          + '<span class="md-alert-icon">' + (ICON[sev] || ICON.note) + '</span>'
          + '<span>' + esc(title) + '</span></div>'
          + (body.length ? '<div class="md-alert-body">' + blockHtml(body.join('\n')) + '</div>' : '')
          + '</div>');
      } else {
        out.push(lines[i]);
        i++;
      }
    }
    return out.join('\n');
  },
  css: '.md-alert{margin:1em 0;padding:12px 14px;border-radius:8px;border:1px solid var(--border-strong);background:var(--code-bg);}'
    + '.md-alert-title{display:flex;align-items:center;gap:8px;font-weight:600;margin-bottom:6px;color:var(--text);}'
    + '.md-alert-icon{font-size:14px;line-height:1;}'
    + '.md-alert-body{color:var(--text);}'
    + '.md-alert-body p{margin:0 0 8px;}'
    + '.md-alert-note{border-left:4px solid var(--accent);}'
    + '.md-alert-info{border-left:4px solid #3b82f6;background:#eff6ff;}'
    + '.md-alert-info .md-alert-title{color:#1d4ed8;}'
    + '.md-alert-warning{border-left:4px solid #f59e0b;background:#fffbeb;}'
    + '.md-alert-warning .md-alert-title{color:#92400e;}'
    + '.md-alert-danger{border-left:4px solid #ef4444;background:#fef2f2;}'
    + '.md-alert-danger .md-alert-title{color:#991b1b;}'
    + '.md-alert-success{border-left:4px solid #22c55e;background:#f0fdf4;}'
    + '.md-alert-success .md-alert-title{color:#15803d;}'
});