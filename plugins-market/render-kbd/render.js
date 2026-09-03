// 渲染插件：[[按键]] → <kbd> 键帽（before 钩子：md 文本级替换，浏览器 html:true 直通）
window.__registerRenderPlugin({
  id: 'kbd',
  before: function (md) {
    return md.replace(/\[\[([^\[\]]{1,24})\]\]/g, '<kbd>$1</kbd>');
  },
  css: 'kbd { display:inline-block; padding:1px 6px; border:1px solid var(--border-strong); border-bottom-width:2px; border-radius:5px; background:var(--code-bg); font-family:ui-monospace,Menlo,monospace; font-size:0.85em; color:var(--text); }'
});
