window.__registerRenderPlugin({
  id: 'quote',
  after: function (html) {
    return html.replace(/<blockquote><p>/g, '<blockquote class="fancy"><p>').replace(/<blockquote>/g, '<blockquote class="fancy">');
  },
  css: 'blockquote.fancy { background: var(--accent-soft); border-left:3px solid var(--accent); padding:8px 14px; border-radius:0 8px 8px 0; }'
});
