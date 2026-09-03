// 渲染插件示例：@@小字@@ → <small>（before 钩子，html 直通）
window.__registerRenderPlugin({
  id: 'smalltext',
  before: function (md) {
    return md.replace(/@@([^@]{1,80})@@/g, '<small>$1</small>');
  },
  css: 'small { font-size: 0.82em; color: var(--text-secondary); }'
});
