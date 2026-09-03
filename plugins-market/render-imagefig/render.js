// 渲染插件：图片 → <figure> 相框 + <figcaption> 图注（after 钩子：html 级替换）
// 说明来源：优先 img 的 title 属性，其次 alt 属性（同时从 img 清除 alt 避免重复文字）
// 若图片独自成段（<p><img></p>），会整体替换为 <figure>，避免块级元素嵌套在 <p> 内的非法结构。
window.__registerRenderPlugin({
  id: 'render-imagefig',
  after: function (html) {
    if (typeof html !== 'string') return html || '';

    // 1) 记录已存在 <figure>…</figure> 的范围，避免重复包裹
    var figureRanges = [];
    var opens = [];
    var m;
    var reOpen = /<figure\b[^>]*>/g;
    while ((m = reOpen.exec(html))) opens.push(m.index);
    var closes = [];
    var reClose = /<\/figure>/g;
    while ((m = reClose.exec(html))) closes.push(m.index);
    for (var o = 0; o < opens.length; o++) {
      var s = opens[o];
      var e = -1;
      for (var c = 0; c < closes.length; c++) {
        if (closes[c] > s) { e = closes[c] + 9; closes.splice(c, 1); break; }
      }
      if (e > s) figureRanges.push([s, e]);
    }
    function inExistingFigure(pos) {
      for (var i = 0; i < figureRanges.length; i++) {
        if (pos >= figureRanges[i][0] && pos <= figureRanges[i][1]) return true;
      }
      return false;
    }

    // 2) <p>…</p> 区间（用于识别“图片独自成段”）
    var paras = [];
    var pOpens = [];
    var reP = /<p\b[^>]*>/g;
    while ((m = reP.exec(html))) pOpens.push(m.index);
    var pCloses = [];
    var rePC = /<\/p>/g;
    while ((m = rePC.exec(html))) pCloses.push(m.index);
    for (var o2 = 0; o2 < pOpens.length; o2++) {
      var ps = pOpens[o2];
      var pe = -1;
      for (var c2 = 0; c2 < pCloses.length; c2++) {
        if (pCloses[c2] > ps) { pe = pCloses[c2] + 4; pCloses.splice(c2, 1); break; }
      }
      if (pe > ps) paras.push([ps, pe]);
    }

    // 3) 引号感知的 <img …> 标签扫描（避免属性值里的 ">" 提前截断）
    function findImgs(text) {
      var res = [];
      var re = /<img\b/gi;
      var mm;
      while ((mm = re.exec(text))) {
        var start = mm.index;
        var j = mm.index + mm[0].length;
        var quote = null;
        while (j < text.length) {
          var ch = text[j];
          if (quote) { if (ch === quote) quote = null; }
          else if (ch === '"' || ch === "'") quote = ch;
          else if (ch === '>') break;
          j++;
        }
        var end = j >= text.length ? j : j + 1;
        res.push({ start: start, end: end, tag: text.slice(start, end) });
        re.lastIndex = end;
      }
      return res;
    }
    function attr(tag, name) {
      var re = new RegExp('\\s' + name + '\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\')', 'i');
      var r = re.exec(tag);
      return r ? (r[1] !== undefined ? r[1] : r[2]) : null;
    }
    function stripAttr(tag, name) {
      var re = new RegExp('\\s' + name + '\\s*=\\s*(?:"[^"]*"|\'[^\']*\')', 'i');
      return tag.replace(re, '');
    }
    // 图片是否独自占据一段（周围只剩空白）
    function paragraphAlone(start, end) {
      for (var i = 0; i < paras.length; i++) {
        var ps = paras[i][0];
        var pe = paras[i][1];
        if (start >= ps && end <= pe) {
          var tagEnd = html.indexOf('>', ps);
          if (tagEnd === -1 || tagEnd >= start) continue;
          var leftGap = html.slice(tagEnd + 1, start);
          var rightGap = html.slice(end, pe - 4);
          if (/^\s*$/.test(leftGap) && /^\s*$/.test(rightGap)) return [ps, pe];
        }
      }
      return null;
    }

    // 4) 从后往前处理，避免下标偏移
    var imgs = findImgs(html);
    for (var i = imgs.length - 1; i >= 0; i--) {
      var im = imgs[i];
      if (inExistingFigure(im.start)) continue;
      var caption = attr(im.tag, 'title');
      var newTag = im.tag;
      if (!caption) {
        var alt = attr(im.tag, 'alt');
        if (alt && alt.trim() !== '') { caption = alt; newTag = stripAttr(newTag, 'alt'); }
      }
      var fig = '<figure class="md-figure">' + newTag
        + (caption ? '<figcaption>' + caption + '</figcaption>' : '')
        + '</figure>';
      var alone = paragraphAlone(im.start, im.end);
      var rs = alone ? alone[0] : im.start;
      var re2 = alone ? alone[1] : im.end;
      html = html.slice(0, rs) + fig + html.slice(re2);
    }
    return html;
  },
  css: '.md-figure{margin:1em 0;padding:8px;border:1px solid var(--border-strong);border-radius:10px;background:var(--code-bg);text-align:center;}'
    + '.md-figure img{max-width:100%;border-radius:6px;}'
    + '.md-figure figcaption{margin-top:8px;font-size:0.85em;color:var(--muted);font-style:italic;}'
});