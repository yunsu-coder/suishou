import Foundation

/// 轻量性能记录 —— "设置 → 诊断"页的数据源（只记耗时与次数，不采样内存）。
///
/// 设计约束：
/// · 开销极低：调用侧同步返回，记录动作丢到后台串行队列；
/// · 环形缓冲只留最近 400 条，进程内不增长；
/// · 任何线程可调。
enum PerfLog {
    struct Entry {
        let label: String
        let ms: Double
        let date: Date
    }

    struct Aggregate {
        let label: String
        let count: Int
        let avgMs: Double
        let maxMs: Double
        let lastMs: Double
    }

    struct Snapshot {
        let generatedAt: Date
        /// 按 maxMs 降序
        let aggregates: [Aggregate]
        let counters: [(name: String, count: Int)]
        /// 新的在前
        let recent: [Entry]
    }

    private static let queue = DispatchQueue(label: "marknote.perf", qos: .utility)
    private static var entries: [Entry] = []
    private static var counters: [String: Int] = [:]
    private static let cap = 400

    /// 计数器 +n（索引刷新次数、预览 WebView 重建次数这类"次数"指标）
    static func bump(_ name: String, _ n: Int = 1) {
        queue.async { counters[name, default: 0] += n }
    }

    /// 记录一次操作用时（毫秒）
    static func record(_ label: String, _ ms: Double) {
        queue.async {
            entries.append(Entry(label: label, ms: ms, date: Date()))
            if entries.count > cap { entries.removeFirst(entries.count - cap) }
        }
    }

    /// 包一段同步代码计时（抛错也记）
    static func measure<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let t0 = CFAbsoluteTimeGetCurrent()
        defer { record(label, (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
        return try body()
    }

    static func snapshot() -> Snapshot {
        queue.sync {
            var acc: [String: (n: Int, sum: Double, maxV: Double, last: Double, lastAt: Date)] = [:]
            for e in entries {
                var a = acc[e.label] ?? (0, 0, 0, 0, Date.distantPast)
                a.n += 1
                a.sum += e.ms
                a.maxV = max(a.maxV, e.ms)
                if e.date >= a.lastAt { a.last = e.ms; a.lastAt = e.date }
                acc[e.label] = a
            }
            let aggregates = acc.map { (key, v) in
                Aggregate(label: key, count: v.n, avgMs: v.sum / Double(v.n), maxMs: v.maxV, lastMs: v.last)
            }.sorted { $0.maxMs > $1.maxMs }
            let recent = entries.suffix(30).reversed().map { $0 }
            let counterList = counters.map { (name: $0.key, count: $0.value) }.sorted { $0.name < $1.name }
            return Snapshot(generatedAt: Date(), aggregates: aggregates,
                            counters: counterList, recent: Array(recent))
        }
    }

    static func reset() {
        queue.async {
            entries.removeAll()
            counters.removeAll()
        }
    }
}
