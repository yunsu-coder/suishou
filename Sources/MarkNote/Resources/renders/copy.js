// 渲染插件：代码块复制按钮（after 钩子：向 <pre><code> 追加复制按钮）
// 复制时读取相邻 <code> 文本，兼容 navigator.clipboard / document.execCommand
if (typeof window !== 'undefined' && !window.__marknoteCopyBtn) {
  window.__marknoteCopyBtn = function (btn) {
    var code = btn.parentNode ? btn.parentNode.querySelector('code') : null;
    var text = code ? (code.textContent || '') : '';
    function fallback(t) {
      var ta = document.createElement('textarea');
      ta.value = t;
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      try { document.execCommand('copy'); } catch (e) {}
      document.body.removeChild(ta);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        btn.textContent = '已复制';
        setTimeout(function () { btn.textContent = '复制'; }, 1200);
      }).catch(function () { fallback(text); });
    } else {
      fallback(text);
    }
  };
}

window.__registerRenderPlugin({
  id: 'copy',
  after: function (html) {
    if (typeof html !== 'string' || html.indexOf('<pre') === -1) return html;
    try {
      var doc = new DOMParser().parseFromString(html, 'text/html');
      var pres = doc.querySelectorAll('pre');
      for (var i = 0; i < pres.length; i++) {
        var pre = pres[i];
        if (!pre.querySelector('code')) continue;
        if (pre.querySelector('.marknote-copy-btn')) continue;
        var btn = doc.createElement('button');
        btn.className = 'marknote-copy-btn';
        btn.type = 'button';
        btn.textContent = '复制';
        btn.setAttribute('onclick', '__marknoteCopyBtn(this)');
        pre.appendChild(btn);
      }
      return doc.body.innerHTML;
    } catch (e) {
      return html;
    }
  },
  css: 'pre{position:relative;} .marknote-copy-btn{position:absolute;top:8px;right:8px;font-size:12px;line-height:1;color:var(--accent,#5E81AC);background:var(--code-bg,#E5E9F0);border:1px solid var(--border-strong,#D8DEE9);border-radius:4px;padding:4px 8px;cursor:pointer;opacity:0;transition:opacity .15s ease;} pre:hover .marknote-copy-btn{opacity:1;}'
});
