import SwiftUI
import WebKit

/// 通用站点登录（B 站 / 微博 / 小红书 / 知乎 / 抖音 / 花瓣 / 豆瓣…）：
/// 应用内打开官方登录页，登录完把该站 cookie 存到本机，供采集抓正文与下载素材时携带。
/// cookie 只存本机（`CollectAccountStore`），只在该站自己的域名上使用，点「退出」即清。
struct CollectorSiteLoginSheet: View {
    let site: CollectSite
    /// 完成回调：返回登录态描述（nil = 没登录成功）
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: site.icon)
                    .foregroundStyle(appAppearance.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(_L("登录 \(site.name)", "Sign in to \(site.name)"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(site.hint + _L("　cookie 只存本机。", " Cookies stay on this Mac."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !message.isEmpty {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button(_L("取消", "Cancel")) { dismiss() }
                    .controlSize(.small)
                Button {
                    Task { await finish() }
                } label: {
                    if busy {
                        HStack(spacing: 6) { ProgressView().controlSize(.small); Text(_L("检查登录…", "Checking…")) }
                    } else {
                        Text(_L("完成", "Done"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(appAppearance.accent)
                .controlSize(.small)
                .disabled(busy)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            SiteLoginWebView(url: site.loginURL)
        }
        .frame(width: 900, height: 640)
        .background(Color(nsColor: appAppearance.editorBackground))
    }

    /// 读 WebView cookie → 存档 → 判定登录态
    private func finish() async {
        busy = true
        defer { busy = false }
        let header = await CollectorSiteLogin.collectCookieHeader(for: site)
        CollectAccountStore.standard.setCookie(header, for: site.id)
        let name = await CollectorSiteLogin.displayName(for: site, cookieHeader: header)
        if let name {
            message = _L("已登录：\(name)", "Signed in: \(name)")
            onDone(name)
            dismiss()
        } else {
            message = _L("还没检测到登录，请在页面里完成登录后再点「完成」",
                         "Not signed in yet — finish signing in, then press Done")
            onDone(nil)
        }
    }
}

/// 站点登录相关的纯逻辑（cookie 拼接 / 登录态查询），便于测试与复用。
@MainActor
enum CollectorSiteLogin {
    static let cookieStore = WKWebsiteDataStore.default()

    /// 现代 Safari 的 UA：WKWebView 默认 UA 会被多数站点判成「浏览器版本过低」
    static var userAgent: String { NotesStore.collectorUA }

    /// 把 cookie 列表拼成请求头（只取该站域名；纯函数，便于测试）
    static func cookieHeader(from cookies: [(name: String, value: String, domain: String)],
                             site: CollectSite) -> String? {
        CollectAccounts.cookieHeader(from: cookies, domains: site.domains)
    }

    /// 从 WebView 的 cookie store 里读出该站 cookie
    static func collectCookieHeader(for site: CollectSite) async -> String? {
        await withCheckedContinuation { cont in
            cookieStore.httpCookieStore.getAllCookies { cookies in
                let list = cookies.map { (name: $0.name, value: $0.value, domain: $0.domain) }
                cont.resume(returning: cookieHeader(from: list, site: site))
            }
        }
    }

    /// 登录态显示名：能拿用户名就拿（B 站 nav），否则按关键 cookie 判「已登录」
    static func displayName(for site: CollectSite, cookieHeader: String?) async -> String? {
        guard let cookieHeader, !cookieHeader.isEmpty else { return nil }
        switch site.check {
        case .bilibiliNav:
            return await bilibiliUserName(cookieHeader: cookieHeader)
        case .cookie(let name):
            return CollectAccounts.header(cookieHeader, containsCookie: name) ? site.name : nil
        case .cookieOnly:
            return site.name
        }
    }

    /// B 站用户名：/x/web-interface/nav（未登录返回 nil）
    static func bilibiliUserName(cookieHeader: String) async -> String? {
        guard let url = URL(string: "https://api.bilibili.com/x/web-interface/nav") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              (dataObj["isLogin"] as? Bool) == true,
              let name = dataObj["uname"] as? String, !name.isEmpty else { return nil }
        return name
    }

    /// 退出登录：清本地 cookie + 清 WebView 里该站的网站数据
    static func logout(_ site: CollectSite) async {
        CollectAccountStore.standard.clear(site.id)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { cont in
            cookieStore.fetchDataRecords(ofTypes: types) { cont.resume(returning: $0) }
        }
        let targets = records.filter { record in
            let n = record.displayName.lowercased()
            return site.domains.contains { n.contains($0.split(separator: ".").first.map(String.init) ?? $0) }
        }
        guard !targets.isEmpty else { return }
        await withCheckedContinuation { cont in
            cookieStore.removeData(ofTypes: types, for: targets) { cont.resume() }
        }
    }
}

// MARK: - 兼容层（B 站老接口，测试与老代码还在用）

@MainActor
enum BilibiliLogin {
    static var userAgent: String { CollectorSiteLogin.userAgent }

    static func cookieHeader(from cookies: [(name: String, value: String, domain: String)]) -> String? {
        guard let site = CollectAccounts.site(id: "bilibili") else { return nil }
        return CollectorSiteLogin.cookieHeader(from: cookies, site: site)
    }

    static func collectCookieHeader() async -> String? {
        guard let site = CollectAccounts.site(id: "bilibili") else { return nil }
        return await CollectorSiteLogin.collectCookieHeader(for: site)
    }

    static func currentUserName() async -> String? {
        var cookie = CollectorPrefs.bilibiliCookie
        if cookie == nil { cookie = await collectCookieHeader() }
        guard let cookie else { return nil }
        return await CollectorSiteLogin.bilibiliUserName(cookieHeader: cookie)
    }

    static func logout() async {
        guard let site = CollectAccounts.site(id: "bilibili") else { return }
        await CollectorSiteLogin.logout(site)
    }
}

/// 登录页用的极简 WKWebView 宿主
private struct SiteLoginWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = CollectorSiteLogin.cookieStore   // 与读取 cookie 用同一个 store
        let web = WKWebView(frame: .zero, configuration: config)
        // 关键：默认 UA 会被不少站点判成「浏览器版本过低」，登录控件直接不渲染
        web.customUserAgent = CollectorSiteLogin.userAgent
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}
