import SwiftUI

/// 站点账号管理：一眼看清各站登没登、能拿到什么好处，随手登录 / 退出。
/// 登录只影响**采集**（抓正文、下素材时带上 cookie），不碰系统浏览器。
struct CollectorAccountsSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// 可注入站点表（默认用内置全表；测试 / 预览渲染小样本时用）
    var sitesOverride: [CollectSite]?
    /// 登录/退出后用于刷新列表
    @State private var tick = 0
    @State private var loginSite: CollectSite?
    /// 站点多了要能搜（按名字 / 域名）
    @State private var query = ""

    private var allSites: [CollectSite] { sitesOverride ?? CollectAccounts.sites }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "person.2.badge.key")
                    .foregroundStyle(appAppearance.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(_L("站点账号", "Site accounts"))
                        .font(.system(size: 13, weight: .semibold))
                    Text(_L("很多站点登录后才给全（微博原图、小红书笔记、知乎长文、花瓣原图…）。cookie 只存本机。",
                            "Many sites need a sign-in to give full results. Cookies stay on this Mac.")
                         + _L("　只收一手优质来源，共 \(allSites.count) 个。",
                              " · curated to first-party sources · \(allSites.count) sites."))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(_L("关闭", "Close")) { dismiss() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField(_L("搜站点（名字或域名）", "Search sites"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            Divider()
            ScrollView { sitesList }
        }
        .frame(width: 580, height: 540)
        .background(Color(nsColor: appAppearance.editorBackground))
        .sheet(item: $loginSite) { site in
            CollectorSiteLoginSheet(site: site) { _ in tick += 1 }
        }
    }

    /// 站点清单（单独抽出来：渲染检查用，ImageRenderer 画不了 ScrollView 内部）
    var sitesList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(SiteGroup.allCases, id: \.self) { group in
                let list = allSites.filter { $0.group == group }.filter(matches)
                if !list.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.title + "（\(list.count)）")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(appAppearance.accent)
                        ForEach(list) { site in
                            row(site).id("\(site.id)-\(tick)")
                        }
                    }
                }
            }
            if allSites.allSatisfy({ !matches($0) }) {
                Text(_L("没搜到这个站点。想要的话把域名给我，我加进去。",
                        "No such site yet — tell me the domain and I'll add it."))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 搜索匹配：名字 / 域名 / id 任一命中
    private func matches(_ site: CollectSite) -> Bool {
        let q = query.trimmed.lowercased()
        guard !q.isEmpty else { return true }
        if site.name.lowercased().contains(q) || site.id.lowercased().contains(q) { return true }
        return site.domains.contains { $0.lowercased().contains(q) }
    }

    private func row(_ site: CollectSite) -> some View {
        let cookie = CollectAccountStore.standard.cookie(site.id)
        let logged = CollectAccounts.looksLoggedIn(site, cookieHeader: cookie)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: site.icon)
                .font(.system(size: 14))
                .frame(width: 20)
                .foregroundStyle(logged ? appAppearance.accent
                                        : Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.45)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(site.name)
                        .font(.system(size: 12, weight: .medium))
                    Text(logged ? _L("已登录", "signed in") : _L("未登录", "not signed in"))
                        .font(.system(size: 10))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Capsule().fill(appAppearance.accent.opacity(logged ? 0.16 : 0.08)))
                        .foregroundStyle(logged ? appAppearance.accent : Color.secondary)
                }
                Text(site.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(nsColor: appAppearance.editorForeground).opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Button(logged ? _L("重新登录", "Sign in again") : _L("登录…", "Sign in…")) {
                    loginSite = site
                }
                .controlSize(.small)
                if logged {
                    Button(_L("退出", "Sign out")) {
                        Task {
                            await CollectorSiteLogin.logout(site)
                            tick += 1
                        }
                    }
                    .controlSize(.small)
                    .foregroundStyle(.secondary)
                }
                if let home = URL(string: "https://\(site.domains.first ?? "")") {
                    Button(_L("打开站点", "Open site")) { NSWorkspace.shared.open(home) }
                        .controlSize(.small)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: appAppearance.surface ?? appAppearance.editorBackground)))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(Color(nsColor: appAppearance.editorForeground.withAlphaComponent(0.08))))
    }
}
