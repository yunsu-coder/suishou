// 渲染插件：状态徽章（before 钩子：md 文本级替换）
// 行内： [badge:成功]  /  [badge:新功能|purple]
// 区块： :::badge 成功 green\n 说明文字\n :::
window.__registerRenderPlugin({
  id: 'render-badge',
  before: function (md) {
    if (typeof md !== 'string') return md || '';
    var COLORS = ['red','orange','yellow','green','blue','purple','gray','grey','ink','accent','success','warning','danger','info','note','ok'];

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
    function isColor(w) {
      var c = String(w || '').toLowerCase();
      return COLORS.indexOf(c) !== -1;
    }
    function colorOf(t) {
      t = String(t || '').toLowerCase();
      if (/完成|成功|通过|green|success|done|ok/.test(t)) return 'green';
      if (/危险|失败|错误|error|danger|fail|red/.test(t)) return 'red';
      if (/警告|警示|warn|warning|orange/.test(t)) return 'orange';
      if (/提示|信息|info|blue/.test(t)) return 'blue';
      if (/进行|process|running|待|pending|gray|grey/.test(t)) return 'gray';
      if (/紫色|purple/.test(t)) return 'purple';
      return 'accent';
    }
    function pill(text, color) {
      color = isColor(color) ? color : colorOf(text);
      return '<span class="md-badge md-badge-' + color + '">' + esc(text) + '</span>';
    }

    // 1) 行内 [badge:状态] 或 [badge:状态|颜色]
    md = md.replace(/\[badge:([^\]]+)\]/g, function (m, inner) {
      var parts = String(inner).split('|');
      var label = (parts[0] || '').trim();
      if (!label) return m;
      var color = parts[1] ? parts[1].trim() : '';
      return pill(label, color);
    });

    // 2) 区块 :::badge 状态 [颜色] ... :::
    var lines = md.split(/\r?\n/);
    var out = [];
    var i = 0;
    while (i < lines.length) {
      var m2 = /^:::\s*badge\b\s*([\s\S]*)$/.exec(lines[i]);
      if (m2) {
        var rest = (m2[1] || '').trim();
        var label = rest;
        var color = '';
        var tk = rest.split(/\s+/);
        if (tk.length >= 2 && isColor(tk[tk.length - 1])) {
          color = tk[tk.length - 1];
          label = tk.slice(0, -1).join(' ');
        }
        if (!label) label = '徽章';
        i++;
        var body = [];
        while (i < lines.length && !/^:::\s*$/.test(lines[i])) { body.push(lines[i]); i++; }
        if (i < lines.length && /^:::\s*$/.test(lines[i])) i++;
        out.push('<div class="md-badge-block"><span class="md-badge md-badge-big md-badge-'
          + (isColor(color) ? color : colorOf(label)) + '">' + esc(label) + '</span>'
          + (body.length ? '<div class="md-badge-body">' + blockHtml(body.join('\n')) + '</div>' : '')
          + '</div>');
      } else {
        out.push(lines[i]);
        i++;
      }
    }
    return out.join('\n');
  },
  css: '.md-badge{display:inline-block;padding:2px 10px;border-radius:999px;font-size:0.78em;font-weight:600;line-height:1.5;background:var(--code-bg);color:var(--text);border:1px solid var(--border-strong);vertical-align:middle;}'
    + '.md-badge-green{background:#ecfdf5;color:#047857;border-color:#a7f3d0;}'
    + '.md-badge-red{background:#fef2f2;color:#b91c1c;border-color:#fecaca;}'
    + '.md-badge-orange{background:#fffbeb;color:#b45309;border-color:#fde68a;}'
    + '.md-badge-yellow{background:#fefce8;color:#a16207;border-color:#fef08a;}'
    + '.md-badge-blue{background:#eff6ff;color:#1d4ed8;border-color:#bfdbfe;}'
    + '.md-badge-purple{background:#f5f3ff;color:#6d28d9;border-color:#ddd6fe;}'
    + '.md-badge-gray{background:#f3f4f6;color:#4b5563;border-color:#e5e7eb;}'
    + '.md-badge-accent{background:var(--accent);color:#fff;border-color:var(--accent);}'
    + '.md-badge-block{margin:1em 0;padding:12px 14px;border:1px solid var(--border-strong);border-radius:12px;background:var(--code-bg);}'
    + '.md-badge-big{font-size:0.9em;}'
    + '.md-badge-body{margin-top:8px;color:var(--text);}'
    + '.md-badge-body p{margin:0 0 8px;}'
});