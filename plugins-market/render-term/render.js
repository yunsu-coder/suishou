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
  css: '.term { background:#0d1117; border:1px solid #30363d; border-radius:8px; padding:10px 14px; overflow:auto; } .term pre { margin:0; color:#7ee787; font-family:ui-monospace,Menlo,monospace; font-size:13px; }'
});
