import CFNetwork
import Foundation

/// 采集插件的网络会话：可选走**本机代理**（访问 X / YouTube 等站点时基本必需）。
///
/// 只管采集：不动系统代理设置，不影响编辑器、预览与其它插件。
/// 代理地址写成 `host:port`（也接受 `http://host:port`），留空 = 直连。
enum CollectorNet {

    /// 解析代理地址（纯函数，便于测试）
    static func parseProxy(_ raw: String?) -> (host: String, port: Int)? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        for prefix in ["http://", "https://", "socks5://", "socks://"] where s.lowercased().hasPrefix(prefix) {
            s = String(s.dropFirst(prefix.count))
            break
        }
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = s.split(separator: ":")
        guard parts.count == 2, let port = Int(parts[1]), (1...65535).contains(port) else { return nil }
        let host = String(parts[0]).trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return nil }
        return (host, port)
    }

    /// 当前设置里的代理（`CollectorPrefs.proxy`）
    static var parsedProxy: (host: String, port: Int)? { parseProxy(CollectorPrefs.proxy) }

    /// 采集统一使用的会话配置
    static var configuration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        if let p = parsedProxy {
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: 1,
                kCFNetworkProxiesHTTPProxy as String: p.host,
                kCFNetworkProxiesHTTPPort as String: p.port,
                "HTTPSEnable": 1,
                "HTTPSProxy": p.host,
                "HTTPSPort": p.port,
            ]
        }
        return config
    }

    private static var cached: URLSession?

    /// 采集用的 URLSession（代理改动后调用 `rebuild()` 立刻生效）
    static var session: URLSession {
        if let cached { return cached }
        let s = URLSession(configuration: configuration)
        cached = s
        return s
    }

    static func rebuild() {
        cached?.invalidateAndCancel()
        cached = nil
    }

    /// 一句话说明当前网络状态（界面上提示用）
    static var statusText: String {
        if let p = parsedProxy {
            return _L("采集走代理 \(p.host):\(p.port)", "Collector uses proxy \(p.host):\(p.port)")
        }
        return _L("采集直连（访问 X / YouTube 等站点常需要代理）",
                  "Direct connection (a proxy is usually required for X / YouTube)")
    }
}
