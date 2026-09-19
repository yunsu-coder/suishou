// 渲染插件：连续的 "- [label] content" 行 → 竖排时间轴（before 钩子：md 文本级替换）
// 用法：
//   - [2024-05] 发布新版本
//   - [阶段一] 完成初稿
window.__registerRenderPlugin({
  id: 'render-timeline',
  before: function (md) {
    if (typeof md !== 'string') return md || '';
    var lines = md.split(/\r?\n/);
    var out = [];
    var group = [];
    var RE = /^(\s*)-(\s+)\[([^\]]+)\]\s*(.*)$/;

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
    function parse(line) {
      var m = RE.exec(line);
      if (!m) return null;
      var label = (m[3] || '').trim();
      // 跳过任务清单：- [ ] / - [x]
      if (label === '' || /^[xX]$/.test(label)) return null;
      return { raw: line, label: label, text: (m[4] || '').trim() };
    }
    function flush() {
      if (group.length >= 2) {
        var html = '<div class="md-timeline">';
        for (var i = 0; i < group.length; i++) {
          var it = group[i];
          html += '<div class="md-tl-item"><span class="md-tl-dot"></span><div class="md-tl-body">'
            + '<span class="md-tl-label">' + esc(it.label) + '</span>'
            + '<span class="md-tl-text">' + inline(it.text) + '</span>'
            + '</div></div>';
        }
        html += '</div>';
        out.push(html);
      } else {
        for (var j = 0; j < group.length; j++) out.push(group[j].raw);
      }
      group = [];
    }
    for (var k = 0; k < lines.length; k++) {
      var item = parse(lines[k]);
      if (item) { group.push(item); }
      else { flush(); out.push(lines[k]); }
    }
    flush();
    return out.join('\n');
  },
  css: '.md-timeline{position:relative;margin:14px 0;padding-left:26px;}'
    + '.md-timeline::before{content:"";position:absolute;left:7px;top:6px;bottom:6px;width:2px;border-radius:2px;background:var(--border-strong);}'
    + '.md-tl-item{position:relative;padding:4px 0 14px;}'
    + '.md-tl-item:last-child{padding-bottom:2px;}'
    + '.md-tl-dot{position:absolute;left:-25px;top:8px;width:10px;height:10px;border-radius:50%;background:var(--accent);box-shadow:0 0 0 3px var(--code-bg);}'
    + '.md-tl-label{display:inline-block;font-weight:600;color:var(--accent);margin-right:8px;}'
    + '.md-tl-text{display:inline;color:var(--text);}'
});