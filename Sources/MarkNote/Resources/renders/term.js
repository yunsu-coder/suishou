window.__registerRenderPlugin({
  id: 'term',
  before: function (md) {
    return md.replace(/(^|\n)((?:\$ .*(?:\n|$))+)/g, function (m, pre, block) {
      var lines = block.trim().split('\n');
      var esc = lines.map(function (l) {
        return l.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
      }).join('\n');
      return pre + '<div class="term"><pre>' + esc + '</pre></div>';
    });
  },
  css: '.term { background:var(--code-bg); border:1px solid var(--border-strong); border-radius:10px; padding:10px 14px; overflow:auto; } .term pre { margin:0; color:var(--hl-str); font-family:var(--theme-code-font,ui-monospace,Menlo,monospace); font-size:13px; }'
});
