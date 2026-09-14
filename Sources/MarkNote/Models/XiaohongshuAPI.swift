import Foundation

/// 小红书专用采集：**读页面渲染后的 DOM**，不碰签名。
///
/// 参考开源实现：MediaCrawler（★64k，Playwright/CDP 模式就是「浏览器渲染 + 解析页面」；
/// 另一种「页面内调签名接口」的方式需要额外喂 `X-s-common` 签名 JS，这里不采用）、
/// Spider_XHS、xhshow。我们复用应用内 WKWebView 的登录态，等页面自己把内容画出来再读。
///
/// 返回 nil = 没登录 / 页面结构变了 / 网络失败（调用方回落到通用搜索或报原因）。
@MainActor
enum XiaohongshuAPI {

    static let home = URL(string: "https://www.xiaohongshu.com/explore")!

    /// 搜索页地址（页面自己会请求接口并渲染卡片）
    static func searchURL(keyword: String) -> URL? {
        var comp = URLComponents(string: "https://www.xiaohongshu.com/search_result")
        comp?.queryItems = [.init(name: "keyword", value: keyword), .init(name: "source", value: "web_explore_feed")]
        return comp?.url
    }

    /// 笔记地址（带 xsec_token 才看得到；没有 token 也先试一把）
    static func noteURL(noteID: String, xsecToken: String?) -> URL? {
        var s = "https://www.xiaohongshu.com/explore/\(noteID)"
        if let token = xsecToken, !token.isEmpty { s += "?xsec_token=\(token)&xsec_source=pc_search" }
        return URL(string: s)
    }

    // MARK: - 搜索笔记

    /// 关键词搜笔记 → 采集候选。
    /// 用「渲染后读 DOM」的方式：搜索页自己会请求接口并画卡片，我们只读结果（不碰签名）。
    /// （接口截获那条路见 `parseSearchAPI`，留着以后换用。）
    static func search(keyword: String, count: Int = 20) async -> [CollectCandidate] {
        guard let url = searchURL(keyword: keyword) else { return [] }
        let wait = "document.querySelectorAll('a[href*=\"/explore/\"]').length >= 3"
        let extract = """
        const cards = [];
        const seen = new Set();
        document.querySelectorAll('a[href*="/explore/"]').forEach(a => {
          const href = a.getAttribute('href') || '';
          const m = href.match(/\\/explore\\/([0-9a-fA-F]+)/);
          if (!m || seen.has(m[1])) return;
          const box = a.closest('section, div');
          const img = (box && box.querySelector('img')) || a.querySelector('img');
          const text = (box && box.innerText)
              ? box.innerText.split('\\n').map(t => t.trim()).filter(Boolean) : [];
          const title = text.find(t => t.length > 4 && !t.startsWith('@')) || text[0] || '';
          const author = (text.find(t => t.startsWith('@')) || '').replace('@', '');
          const cover = img ? (img.currentSrc || img.src || img.getAttribute('data-src') || '') : '';
          seen.add(m[1]);
          cards.push({id: m[1], title: title, author: author, cover: cover});
        });
        return JSON.stringify(cards.slice(0, \(max(8, min(count, 60)))));
        """
        guard let json = await CollectorWebRender.scrape(url, waitForJS: wait, extractJS: extract,
                                                         readyTimeout: 10) else {
            return []
        }
        return parseCards(json)
    }

    /// 截获的搜索接口响应 → 候选
    static func parseSearchAPI(_ capturedJSON: String, limit: Int = 40) -> [CollectCandidate] {
        guard let data = capturedJSON.data(using: .utf8),
              let caps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var out: [CollectCandidate] = []
        for cap in caps {
            guard let body = cap["body"] as? String,
                  let bodyData = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let items = (obj["data"] as? [String: Any])?["items"] as? [[String: Any]] else { continue }
            for item in items {
                guard let card = item["note_card"] as? [String: Any],
                      let noteID = item["id"] as? String ?? card["note_id"] as? String else { continue }
                let token = (item["xsec_token"] as? String) ?? (card["xsec_token"] as? String) ?? ""
                var urlString = "https://www.xiaohongshu.com/explore/\(noteID)"
                if !token.isEmpty { urlString += "?xsec_token=\(token)&xsec_source=pc_search" }
                guard let page = URL(string: urlString) else { continue }
                let title = ((card["display_title"] as? String) ?? (card["title"] as? String) ?? "").trimmed
                let author = (card["user"] as? [String: Any])?["nickname"] as? String
                let cover = ((card["cover"] as? [String: Any])?["url_default"] as? String)
                    ?? ((card["cover"] as? [String: Any])?["url"] as? String)
                let likes = ((card["interact_info"] as? [String: Any])?["liked_count"] as? String)
                var c = CollectCandidate(id: noteID, kind: "image",
                                         title: title.isEmpty ? "小红书笔记 \(noteID.suffix(6))" : title,
                                         thumbURL: cover.flatMap { $0.hasPrefix("http") ? URL(string: $0) : nil },
                                         fullURL: nil, pageURL: page, duration: nil)
                c.sourceLabel = "小红书"
                c.metaLine = [author.map { "@\($0)" }, likes.map { "\($0) 赞" }, "笔记"]
                    .compactMap { $0 }.joined(separator: " · ")
                out.append(c)
                if out.count >= limit { break }
            }
            if out.count >= limit { break }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.id).inserted }
    }

    /// DOM 卡片 → 候选
    static func parseCards(_ json: String) -> [CollectCandidate] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var out: [CollectCandidate] = []
        for item in items {
            guard let noteID = item["id"] as? String else { continue }
            let title = (item["title"] as? String)?.trimmed ?? ""
            let author = (item["author"] as? String)?.trimmed
            let token = (item["token"] as? String)?.trimmed ?? ""
            var urlString = "https://www.xiaohongshu.com/explore/\(noteID)"
            if !token.isEmpty { urlString += "?xsec_token=\(token)&xsec_source=pc_search" }
            guard let page = URL(string: urlString) else { continue }
            var c = CollectCandidate(id: noteID, kind: "image",
                                     title: title.isEmpty ? "小红书笔记 \(noteID.suffix(6))" : title,
                                     thumbURL: (item["cover"] as? String).flatMap { s in
                                         s.hasPrefix("http") ? URL(string: s) : nil
                                     },
                                     fullURL: nil, pageURL: page, duration: nil)
            c.sourceLabel = "小红书"
            let likes = (item["likes"] as? String)?.trimmed
            c.metaLine = [author.map { "@\($0)" }, likes.map { "\($0) 赞" }, "笔记"]
                .compactMap { $0 }.joined(separator: " · ")
            out.append(c)
        }
        return out
    }

    // MARK: - 笔记详情 → 全部图片

    /// 取一条笔记的全部图片：**让页面自己点进去**（笔记详情页需要 SPA 内部才有的 xsec_token，
    /// 直接拼 URL 会 404「当前笔记暂时无法浏览」）。
    ///
    /// 现在改成：直接打开**带 xsec_token 的笔记页**（token 从搜索接口的截获响应里拿到），
    /// 笔记页会自己请求 `/api/sns/web/v1/feed`，我们再把响应截下来读 `image_list`。
    static func noteImages(noteID: String, xsecToken: String?) async -> [URL] {
        guard let url = noteURL(noteID: noteID, xsecToken: xsecToken) else { return [] }
        guard let captured = await CollectorWebRender.captureAPI(
            url, urlKeyword: "/api/sns/web/v1/feed",
            readyJS: "(window.__cap && window.__cap.some(c => c.body.indexOf('image_list') >= 0))") else {
            return []
        }
        return parseFeedAPI(captured)
    }

    /// 截获的笔记详情响应 → 图片列表
    static func parseFeedAPI(_ capturedJSON: String) -> [URL] {
        guard let data = capturedJSON.data(using: .utf8),
              let caps = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        var out: [URL] = []
        for cap in caps {
            guard let body = cap["body"] as? String,
                  let bodyData = body.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
                  let items = (obj["data"] as? [String: Any])?["items"] as? [[String: Any]] else { continue }
            for item in items {
                guard let card = item["note_card"] as? [String: Any],
                      let list = card["image_list"] as? [[String: Any]] else { continue }
                for image in list {
                    for key in ["url_default", "url", "url_pre", "url_default_webp"] {
                        if let s = image[key] as? String, let u = URL(string: s) {
                            out.append(u)
                            break
                        }
                    }
                }
            }
        }
        var seen = Set<String>()
        return out.filter { seen.insert($0.absoluteString).inserted }
    }

    /// 兜底（DOM 方式）：在搜索结果页点开笔记再读图片。接口方式失败时用。
    static func noteImagesByClicking(noteID: String, keyword: String) async -> [URL] {
        guard let url = searchURL(keyword: keyword) else { return [] }
        guard let session = await CollectorWebRender.openSession(url) else { return [] }
        defer { session.close() }
        // ① 等卡片出来，然后点开目标笔记（点一下就返回，别在页面里长时间 await）
        _ = await session.run("""
        const id = \(jsString(noteID));
        for (let i = 0; i < 30; i++) {
          const a = [...document.querySelectorAll('a[href*="/explore/"]')]
            .find(x => (x.getAttribute('href') || '').includes(id));
          if (a) {
            // 卡片是 target="_blank"：直接点会弹新窗口，这里派发一次普通点击交给站点处理
            a.removeAttribute('target');
            a.click();
            return JSON.stringify({clicked: true});
          }
          await new Promise(r => setTimeout(r, 300));
        }
        return JSON.stringify({clicked: false});
        """)
        // ①' 如果站点还是走了弹窗，就把弹窗地址接过来自己打开
        try? await Task.sleep(nanoseconds: 800_000_000)
        _ = await session.followPopup()
        // ② 分次轮询笔记视图的数据
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if let json = await session.run(Self.readNoteStateJS(noteID: noteID)) {
                let urls = parseImageList(json)
                if !urls.isEmpty { return urls }
            }
        }
        // ③ 实在不行：直接抓 DOM 大图
        if let json = await session.run(Self.readDOMImagesJS()) {
            return parseImageList(json)
        }
        return []
    }

    /// 读笔记视图状态（`__INITIAL_STATE__.note.noteDetailMap`）里的图片列表；没有就返回 `[]`
    static func readNoteStateJS(noteID: String) -> String {
        """
        const id = \(jsString(noteID));
        try {
          const map = window.__INITIAL_STATE__ && window.__INITIAL_STATE__.note
                      && window.__INITIAL_STATE__.note.noteDetailMap;
          if (!map) return JSON.stringify([]);
          const entry = map[id] || map[Object.keys(map)[0]];
          const list = entry && entry.note && entry.note.imageList;
          if (!list || !list.length) return JSON.stringify([]);
          const urls = list.map(img => img.urlDefault || img.url || img.urlPre || img.urlDefaultWebp)
                           .filter(u => u && u.startsWith('http'));
          return JSON.stringify([...new Set(urls)]);
        } catch (e) { return JSON.stringify([]); }
        """
    }

    /// 读 DOM 里的大图（跳过头像 / 图标）
    static func readDOMImagesJS() -> String {
        """
        const urls = [];
        const seen = new Set();
        document.querySelectorAll('img').forEach(img => {
          const src = img.currentSrc || img.src || img.getAttribute('data-src') || '';
          if (!src.startsWith('http')) return;
          if (!/xhscdn|sns-webpic|ci\\.xiaohongshu/.test(src)) return;
          if (/avatar|emoji|icon|logo/i.test(src)) return;
          if ((img.naturalWidth || img.clientWidth || 0) < 300) return;
          const clean = src.split('?')[0];
          if (seen.has(clean)) return;
          seen.add(clean);
          urls.push(src);
        });
        return JSON.stringify(urls);
        """
    }

    /// DOM 图片列表 JSON → URL
    static func parseImageList(_ json: String) -> [URL] {
        guard let data = json.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [String] else { return [] }
        var out: [URL] = []
        for s in list { if let u = URL(string: s) { out.append(u) } }
        return out
    }

    /// 调试用：报告页面加载情况（地址 / 标题 / 签名函数在不在 / 正文长度）
    static func rawPageProbe() async -> String? {
        let js = """
        const info = {
          href: location.href,
          title: document.title,
          hasSign: typeof window._webmsxyw,
          hasSignCommon: typeof window._webmsxyw_common,
          bodyLen: (document.body ? document.body.innerText.length : -1),
          head: (document.body ? document.body.innerText.slice(0, 120) : "")
        };
        return JSON.stringify(info);
        """
        return await CollectorWebRender.runJS(js, on: home)
    }

    /// 调试用：点开笔记后拿到的原始结果（未解析，便于看 `{error:…}` 之类）
    static func rawNoteImages(keyword: String, noteID: String) async -> String? {
        guard let url = searchURL(keyword: keyword) else { return nil }
        let wait = "document.querySelectorAll('a[href*=\"/explore/\"]').length >= 3"
        let extract = """
        const noteID = \(jsString(noteID));
        const target = [...document.querySelectorAll('a[href*="/explore/"]')]
          .find(a => (a.getAttribute('href') || '').includes(noteID));
        if (!target) return JSON.stringify({error: 'card-not-found', id: noteID});
        target.click();
        let lastState = '';
        for (let i = 0; i < 25; i++) {
          await new Promise(r => setTimeout(r, 200));
          const st = window.__INITIAL_STATE__;
          const map = st && st.note && st.note.noteDetailMap;
          lastState = st ? Object.keys(st.note || {}).join(',') : 'no-state';
          if (map && Object.keys(map).length) {
            const entry = map[noteID] || map[Object.keys(map)[0]];
            const note = entry && entry.note;
            return JSON.stringify({mapKeys: Object.keys(map).slice(0, 3),
                                   noteKeys: note ? Object.keys(note).slice(0, 20) : null,
                                   imageCount: (note && note.imageList) ? note.imageList.length : -1,
                                   href: location.href});
          }
        }
        return JSON.stringify({error: 'no-note-view', noteKeys: lastState, href: location.href});
        """
        return await CollectorWebRender.scrape(url, waitForJS: wait, extractJS: extract,
                                               readyTimeout: 10, loadTimeout: 20)
    }

    /// 调试用：笔记页里 `__INITIAL_STATE__` 的结构探针
    static func rawNoteProbe(noteID: String, xsecToken: String?) async -> String? {
        guard let url = noteURL(noteID: noteID, xsecToken: xsecToken) else { return nil }
        let wait = "!!(window.__INITIAL_STATE__ || document.querySelectorAll('img').length >= 3)"
        let extract = """
        const st = window.__INITIAL_STATE__;
        const out = {
          href: location.href,
          title: document.title,
          stateType: typeof st,
          stateKeys: st ? Object.keys(st).slice(0, 14) : [],
          noteKeys: (st && st.note) ? Object.keys(st.note).slice(0, 14) : [],
          detailKeys: (st && st.note && st.note.noteDetailMap)
              ? Object.keys(st.note.noteDetailMap).slice(0, 4) : [],
          firstEntryKeys: null,
          firstNoteKeys: null,
          imageCount: 0,
          imgTags: document.querySelectorAll('img').length,
          bodyHead: (document.body ? document.body.innerText.slice(0, 160) : '')
        };
        try {
          const map = st && st.note && st.note.noteDetailMap;
          if (map && Object.keys(map).length) {
            const first = map[Object.keys(map)[0]];
            out.firstEntryKeys = first ? Object.keys(first).slice(0, 14) : [];
            const note = first && first.note;
            out.firstNoteKeys = note ? Object.keys(note).slice(0, 20) : [];
            out.imageCount = (note && note.imageList) ? note.imageList.length : -1;
          }
        } catch (e) { out.err = String(e); }
        return JSON.stringify(out);
        """
        return await CollectorWebRender.scrape(url, waitForJS: wait, extractJS: extract,
                                               readyTimeout: 8, loadTimeout: 20)
    }

    /// 调试用：搜索页里 `__INITIAL_STATE__.search` 的结构探针
    static func rawSearchProbe(keyword: String) async -> String? {
        guard let url = searchURL(keyword: keyword) else { return nil }
        let wait = "document.querySelectorAll('a[href*=\"/explore/\"]').length >= 3"
        let extract = """
        const st = window.__INITIAL_STATE__;
        const s = st && st.search;
        const out = {
          searchKeys: s ? Object.keys(s).slice(0, 24) : [],
          feedsType: s && s.feeds ? (Array.isArray(s.feeds) ? 'array' : typeof s.feeds) : 'none',
          feedsLen: s && s.feeds ? (Array.isArray(s.feeds) ? s.feeds.length : Object.keys(s.feeds).length) : 0,
          firstFeedKeys: null, firstCardKeys: null, tokenSample: '', hrefSample: '',
          links: document.querySelectorAll('a[href*="/explore/"]').length
        };
        try {
          let f = s && s.feeds;
          if (f && !Array.isArray(f)) f = Object.values(f);
          const first = f && f[0];
          out.firstFeedKeys = first ? Object.keys(first).slice(0, 20) : null;
          out.firstCardKeys = first && (first.noteCard || first.note_card)
              ? Object.keys(first.noteCard || first.note_card).slice(0, 24) : null;
          out.tokenSample = first ? String(first.xsecToken || first.xsec_token || '') .slice(0, 12) : '';
        } catch (e) { out.err = String(e); }
        // 深入一层：feeds.map 里到底存了什么（小红书把状态归一化过）
        try {
          const f = s && s.feeds;
          const map = f && f.map;
          out.mapType = Array.isArray(map) ? 'array' : typeof map;
          out.mapLen = map ? (Array.isArray(map) ? map.length : Object.keys(map).length) : 0;
          let firstVal = null;
          if (Array.isArray(map)) firstVal = map[0];
          else if (map) firstVal = map[Object.keys(map)[0]];
          out.mapValueKeys = (firstVal && typeof firstVal === 'object') ? Object.keys(firstVal).slice(0, 24) : null;
          out.mapValueSample = firstVal ? JSON.stringify(firstVal).slice(0, 300) : '';
          // 有的版本把结果放在 rawValue / value 里
          const raw = f && (f.rawValue || f.value || f._rawValue || f._value);
          out.rawType = raw ? (Array.isArray(raw) ? 'array' : typeof raw) : 'none';
        } catch (e) { out.err2 = String(e); }
        const a = document.querySelector('a[href*="/explore/"]');
        out.hrefSample = a ? a.getAttribute('href').slice(0, 120) : '';
        return JSON.stringify(out);
        """
        return await CollectorWebRender.scrape(url, waitForJS: wait, extractJS: extract,
                                               readyTimeout: 10, loadTimeout: 20)
    }

    // MARK: - 小工具

    /// JSON 字符串转义（拼进 JS）
    static func jsString(_ s: String) -> String {
        var out = "\""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if ch.value < 0x20 {
                    out += String(format: "\\u%04x", ch.value)
                } else {
                    out.unicodeScalars.append(ch)
                }
            }
        }
        return out + "\""
    }

}
