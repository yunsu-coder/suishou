import SwiftUI
import WebKit

/// B 站登录：应用内打开官方登录页（扫码/账号密码都行），登录成功后把 WebView 里的
/// bilibili cookie 拼成请求头交给采集器 —— 采集接口带着它就能拿到 1080P。
/// cookie 只存本机（`CollectorPrefs`），不外传。
struct CollectorBilibiliLoginSheet: View {
    /// 完成回调：返回用户名（nil = 没登录成功）
    let onDone: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var message = ""

    private let loginURL = URL(string: "https://passport.bilibili.com/login")!

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.badge.key")
                    .foregroundStyle(appAppearance.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(_L("登录 B 站", "Sign in to Bilibili"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(_L("登录后采集才能下载 1080P；不登录只有 360P。cookie 只存本机。",
                            "Sign in to download 1080p; otherwise only 360p. Cookies stay on this Mac."))
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
            BilibiliWebView(url: loginURL)
        }
        .frame(width: 900, height: 640)
        .background(Color(nsColor: appAppearance.editorBackground))
    }

    /// 读取 WebView 里的 bilibili cookie → 存起来 → 用 nav 接口核对是否真的登录
    private func finish() async {
        busy = true
        defer { busy = false }
        let header = await BilibiliLogin.collectCookieHeader()
        CollectorPrefs.bilibiliCookie = header
        let user = await BilibiliLogin.currentUserName()
        if let user {
            message = _L("已登录：\(user)", "Signed in: \(user)")
        } else {
            message = _L("还没有登录成功", "Not signed in yet")
        }
        onDone(user)
        if user != nil { dismiss() }
    }
}

/// B 站登录相关的纯逻辑（cookie 拼接 / 登录态查询），便于测试与复用。
@MainActor
enum BilibiliLogin {
    static let cookieStore = WKWebsiteDataStore.default()

    /// 现代 Safari 的 UA：WKWebView 默认 UA 没有 `Version/… Safari/…` 段，
    /// B 站登录页会判定「浏览器版本过低」拒绝渲染登录控件。
    static var userAgent: String { NotesStore.collectorUA }

    /// 把 cookie 列表拼成请求头：只取 bilibili 域名、只留非空值（纯函数，便于测试）
    static func cookieHeader(from cookies: [(name: String, value: String, domain: String)]) -> String? {
        let picked = cookies.filter { $0.domain.lowercased().contains("bilibili.com") && !$0.value.isEmpty }
        guard !picked.isEmpty else { return nil }
        // 同名 cookie 只留一条（域越具体越优先）
        var byName: [String: String] = [:]
        for c in picked.sorted(by: { $0.domain.count < $1.domain.count }) { byName[c.name] = c.value }
        let header = byName.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: "; ")
        return header.isEmpty ? nil : header
    }

    /// 从 WebView 的 cookie store 里读出 bilibili cookie 并保存
    static func collectCookieHeader() async -> String? {
        await withCheckedContinuation { cont in
            cookieStore.httpCookieStore.getAllCookies { cookies in
                let list = cookies.map { (name: $0.name, value: $0.value, domain: $0.domain) }
                cont.resume(returning: cookieHeader(from: list))
            }
        }
    }

    /// 当前登录用户名（未登录返回 nil）：/x/web-interface/nav
    static func currentUserName() async -> String? {
        var cookie = CollectorPrefs.bilibiliCookie
        if cookie == nil { cookie = await collectCookieHeader() }
        guard let cookie, let url = URL(string: "https://api.bilibili.com/x/web-interface/nav") else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 15
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("https://www.bilibili.com", forHTTPHeaderField: "Referer")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataObj = obj["data"] as? [String: Any],
              (dataObj["isLogin"] as? Bool) == true,
              let name = dataObj["uname"] as? String, !name.isEmpty else { return nil }
        return name
    }

    /// 退出登录：清掉 bilibili 的 WebView cookie 与本地快照
    static func logout() async {
        CollectorPrefs.bilibiliCookie = nil
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records: [WKWebsiteDataRecord] = await withCheckedContinuation { cont in
            cookieStore.fetchDataRecords(ofTypes: types) { cont.resume(returning: $0) }
        }
        let targets = records.filter { $0.displayName.lowercased().contains("bilibili") }
        guard !targets.isEmpty else { return }
        await withCheckedContinuation { cont in
            cookieStore.removeData(ofTypes: types, for: targets) { cont.resume() }
        }
    }
}

/// 登录页用的极简 WKWebView 宿主
private struct BilibiliWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = BilibiliLogin.cookieStore   // 与读取 cookie 用同一个 store
        let web = WKWebView(frame: .zero, configuration: config)
        // 关键：默认 UA 会被 B 站判定为「浏览器版本过低」，登录控件直接不渲染
        web.customUserAgent = BilibiliLogin.userAgent
        web.load(URLRequest(url: url))
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {}
}
