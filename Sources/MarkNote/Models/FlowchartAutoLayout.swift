import Foundation
import WebKit

/// 流程图自动布局 —— **用 dagre**（mermaid / draw.io 那一层的图布局引擎），
/// 而不是我们自己写"该往哪儿摆"的启发式：分层(rank) → 层内排序 → 坐标分配，
/// 是图论里被验证过几十年的成熟做法。这里只负责：
/// 把文档编成 dagre 认识的图 → 在隐藏 WKWebView 里跑一次 → 把坐标写回节点。
enum FlowchartAutoLayout {

    enum Direction: String {
        case topBottom = "TB"     // 纵向（默认，最常用的流程方向）
        case leftRight = "LR"     // 横向（泳道式阅读）
    }

    /// 编 dagre 的输入：节点带尺寸（拿节点自身的 w/h），边只保留两端都在图里的
    /// （悬空边会被 dagre 丢掉，先自己过滤，省得它报错）
    static func graphPayload(_ doc: FCDocument, direction: Direction,
                             nodeSep: Double = 42, rankSep: Double = 60) -> String {
        let ids = Set(doc.nodes.map(\.id))
        var nodes: [[String: Any]] = []
        for n in doc.nodes {
            nodes.append(["id": n.id, "width": max(24, n.w), "height": max(24, n.h)])
        }
        var edges: [[String: Any]] = []
        for e in doc.edges where ids.contains(e.fromNode) && ids.contains(e.toNode) && e.fromNode != e.toNode {
            edges.append(["v": e.fromNode, "w": e.toNode])
        }
        let graph: [String: Any] = [
            "nodes": nodes,
            "edges": edges,
            "rankdir": direction.rawValue,
            "nodeSep": nodeSep,
            "rankSep": rankSep,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: graph)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// 跑一次布局：返回 节点 id → 新左上角坐标（已换算成"左上角"而不是 dagre 的中心点）
    static func layout(_ doc: FCDocument, direction: Direction) async -> [String: CGPoint]? {
        let payload = graphPayload(doc, direction: direction)
        let sizes = Dictionary(uniqueKeysWithValues: doc.nodes.map { ($0.id, CGSize(width: $0.w, height: $0.h)) })
        return await JSBridge.run(payload: payload, sizes: sizes)
    }

    // MARK: - JS 桥（隐藏 WebView；dagre 随包分发，不联网）

    @MainActor
    private final class JSBridge: NSObject, WKNavigationDelegate {
        static var shared: JSBridge?
        private var web: WKWebView?
        private var ready: CheckedContinuation<Bool, Never>?

        static func run(payload: String, sizes: [String: CGSize]) async -> [String: CGPoint]? {
            let bridge = await MainActor.run { () -> JSBridge in
                if let s = JSBridge.shared { return s }
                let s = JSBridge(); JSBridge.shared = s; return s
            }
            await bridge.loadIfNeeded()
            guard let json = await bridge.evaluate(payload) else { return nil }
            return decode(json, sizes: sizes)
        }

        private func loadIfNeeded() async {
            if web != nil { return }
            // dagre 随包分发；但**不能把页面写进 app 包**（只读/签名），
            // 所以把脚本复制到临时目录，与页面一起从临时目录加载。
            guard let src = Bundle.module.url(forResource: "dagre.min", withExtension: "js",
                                              subdirectory: "Resources/vendor") else { return }
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("marknote-fc-layout", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let js = dir.appendingPathComponent("dagre.min.js")
            if !FileManager.default.fileExists(atPath: js.path) {
                try? FileManager.default.copyItem(at: src, to: js)
            }
            let page = dir.appendingPathComponent("fc-layout.html")
            let html = """
            <!doctype html><meta charset="utf-8"><body><script src="dagre.min.js"></script></body>
            """
            try? html.write(to: page, atomically: true, encoding: .utf8)
            let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
            w.navigationDelegate = self
            web = w
            let ok = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                ready = cont
                w.loadFileURL(page, allowingReadAccessTo: dir)
            }
            if !ok { web = nil }
        }

        private func evaluate(_ payload: String) async -> String? {
            guard let web else { return nil }
            let js = """
            (function(){
              try {
                var g = new dagre.graphlib.Graph();
                var cfg = \(payload);
                g.setGraph({ rankdir: cfg.rankdir, nodesep: cfg.nodeSep, ranksep: cfg.rankSep, marginx: 24, marginy: 24 });
                g.setDefaultEdgeLabel(function(){ return {}; });
                cfg.nodes.forEach(function(n){ g.setNode(n.id, { width: n.width, height: n.height }); });
                cfg.edges.forEach(function(e){ g.setEdge(e.v, e.w); });
                dagre.layout(g);
                var out = {};
                cfg.nodes.forEach(function(n){
                  var p = g.node(n.id);
                  if (p) out[n.id] = { x: p.x, y: p.y };
                });
                return JSON.stringify(out);
              } catch (e) { return "ERR:" + e; }
            })()
            """
            return await withCheckedContinuation { cont in
                web.evaluateJavaScript(js) { value, _ in
                    cont.resume(returning: value as? String)
                }
            }
        }

        private static func decode(_ json: String, sizes: [String: CGSize]) -> [String: CGPoint]? {
            guard json.hasPrefix("{"), let data = json.data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] else { return nil }
            var out: [String: CGPoint] = [:]
            for (id, p) in raw {
                guard let x = p["x"], let y = p["y"] else { continue }
                let size = sizes[id] ?? CGSize(width: 140, height: 64)
                // dagre 给的是中心点；文档存左上角
                out[id] = CGPoint(x: x - size.width / 2, y: y - size.height / 2)
            }
            return out.isEmpty ? nil : out
        }

        // MARK: WKNavigationDelegate
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready?.resume(returning: true); ready = nil
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            ready?.resume(returning: false); ready = nil
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            ready?.resume(returning: false); ready = nil
        }
    }
}
