window.__registerRenderPlugin({
  id: 'mention',
  before: function (md) {
    // 仅行首/空格后的 @中文英文下划线（避开 url/邮箱）
    return md.replace(/(^|[^\w/])@([\p{L}\p{N}_\-]{1,24})/gu, '$1<span class="mention">@$2</span>');
  },
  css: '.mention { color: var(--accent); background: var(--accent-soft); border-radius:4px; padding:0 4px; font-weight:600; }'
});
