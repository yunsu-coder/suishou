import Foundation

// MARK: - 模板（插件 kind = templates）
//
// 设计（见 docs/05-内置插件库.md「模板插件」）：
// · 声明式：模板包只给一份 Markdown 正文 + 几个元数据，不执行任何代码；
// · 两种占位：
//   `{{变量}}`  —— 插入时直接替换掉（date / weekday / time / title / folder / selection / cursor）
//   `<#字段:默认值#>` —— 留在正文里由用户填：插入后自动选中第一个，Tab / Shift+Tab 在字段间跳
// · 写出来的文件仍是普通 Markdown（front matter、- [ ]、@due() 都是通用写法）。

struct NoteTemplate: Identifiable, Equatable {
    let id: String
    let name: String
    let nameEn: String?
    let icon: String
    let category: String
    let desc: String
    let descEn: String?
    let body: String
    let bodyEn: String?
    /// 文件名规则（同样支持 `{{变量}}`）；缺省用模板名
    let fileName: String?
    /// 目标目录（相对工作台；空 = 根目录）
    let folder: String?

    var displayName: String { AppLanguage.isEnglish ? (nameEn ?? name) : name }
    var displayDesc: String { AppLanguage.isEnglish ? (descEn ?? desc) : desc }
    var displayBody: String { AppLanguage.isEnglish ? (bodyEn ?? body) : body }
}

/// 展开上下文（插入时能拿到的信息）
struct TemplateContext {
    var title: String = ""
    var folder: String?
    var now: Date = Date()
    /// 当前选中的文字（模板里用 `{{selection}}` 引用）
    var selection: String?
}

/// 展开结果：最终正文 + 需要用户填的字段范围（字符偏移）
struct TemplateExpansion: Equatable {
    var text: String
    /// 字段在 text 中的字符范围（按出现顺序），供编辑器 Tab 跳转
    var fields: [Range<Int>]
    /// `{{cursor}}` 指定的光标位置（没有就用最后一个字段之后 / 文末）
    var cursor: Int?

    var hasFields: Bool { !fields.isEmpty }
}

enum NoteTemplateEngine {
    /// 变量替换 + 字段定位（纯函数，便于测试）
    static func expand(_ template: NoteTemplate, context: TemplateContext) -> TemplateExpansion {
        let source = template.displayBody
        var text = ""
        var fields: [Range<Int>] = []
        var cursor: Int?
        var index = source.startIndex

        func number(_ s: String) -> Int { text.count }

        while index < source.endIndex {
            let rest = source[index...]
            // 字段：<#名字#> 或 <#名字:默认值#>
            if rest.hasPrefix("<#"), let end = rest.range(of: "#>") {
                let inner = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound])
                let parts = inner.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                let fallback = parts.count > 1 ? String(parts[1]) : String(parts[0])
                text += fallback
                fields.append(number(text) - fallback.count ..< number(text))
                index = end.upperBound
                continue
            }
            // 变量：{{name}}
            if rest.hasPrefix("{{"), let end = rest.range(of: "}}") {
                let name = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                if name == "cursor" {
                    cursor = number(text)
                } else if let value = value(for: name, context: context) {
                    text += value
                }
                index = end.upperBound
                continue
            }
            text.append(source[index])
            index = source.index(after: index)
        }
        return TemplateExpansion(text: text, fields: fields, cursor: cursor)
    }

    /// 变量取值；未知变量返回 nil（原样丢弃，避免把 {{xxx}} 留在笔记里）
    static func value(for name: String, context: TemplateContext) -> String? {
        let cal = Calendar(identifier: .gregorian)
        let date = context.now
        switch name {
        case "date":
            return Self.dateFormatter("yyyy-MM-dd").string(from: date)
        case "tomorrow":
            let d = cal.date(byAdding: .day, value: 1, to: date) ?? date
            return Self.dateFormatter("yyyy-MM-dd").string(from: d)
        case "next_week":
            let d = cal.date(byAdding: .day, value: 7, to: date) ?? date
            return Self.dateFormatter("yyyy-MM-dd").string(from: d)
        case "date_cn":
            return Self.dateFormatter("yyyy 年 M 月 d 日").string(from: date)
        case "weekday":
            let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
            let idx = cal.component(.weekday, from: date) - 1
            return names[max(0, min(names.count - 1, idx))]
        case "time":
            return Self.dateFormatter("HH:mm").string(from: date)
        case "year":
            return String(cal.component(.year, from: date))
        case "month":
            return String(format: "%02d", cal.component(.month, from: date))
        case "day":
            return String(format: "%02d", cal.component(.day, from: date))
        case "week":
            let week = cal.component(.weekOfYear, from: date)
            return String(format: "%02d", week)
        case "title":
            return context.title
        case "folder":
            return context.folder ?? ""
        case "selection":
            return context.selection ?? ""
        default:
            return nil
        }
    }

    /// 模板可声明的变量白名单（用于校验模板包，避免写出没人认识的变量）
    static let knownVariables: Set<String> = [
        "date", "date_cn", "tomorrow", "next_week", "weekday", "time", "year", "month", "day", "week",
        "title", "folder", "selection", "cursor",
    ]

    /// 从正文里扫出用到的变量（模板质量校验用）
    static func variables(in body: String) -> Set<String> {
        var out = Set<String>()
        var index = body.startIndex
        while let start = body[index...].range(of: "{{") {
            guard let end = body[start.upperBound...].range(of: "}}") else { break }
            let name = body[start.upperBound..<end.lowerBound].trimmingCharacters(in: .whitespaces)
            out.insert(name)
            index = end.upperBound
        }
        return out
    }

    /// 文件名规则展开（同样只认已知变量；`<#字段#>` 在文件名里不合法，直接剔除）
    static func fileName(_ template: NoteTemplate, context: TemplateContext) -> String {
        let rule = template.fileName ?? template.name
        let expanded = expand(NoteTemplate(id: template.id, name: template.name,
                                           nameEn: template.nameEn, icon: template.icon,
                                           category: template.category, desc: template.desc,
                                           descEn: template.descEn, body: rule,
                                           bodyEn: nil, fileName: nil, folder: template.folder),
                              context: context).text
        // 文件名里不该出现字段标记：真出现就整段去掉（校验会另外拦下来）
        var clean = expanded
        while let start = clean.range(of: "<#"), let end = clean.range(of: "#>", range: start.upperBound..<clean.endIndex) {
            clean.removeSubrange(start.lowerBound..<end.upperBound)
        }
        let stem = NotesStore.noteStem(clean)
        return stem.isEmpty ? template.name : stem
    }

    private static func dateFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f
    }
}

// MARK: - 编辑器里的「填空模式」：字段范围随编辑同步移动

/// 记录字段范围，并在文本被编辑后把后续字段平移（纯值类型，便于测试）
struct TemplateFillPlan: Equatable {
    private(set) var fields: [Range<Int>]
    private(set) var index: Int = 0
    /// 已经离开的字段（用户按 Tab 走过的）不再回跳
    private(set) var visited: Set<Int> = []

    init(expansion: TemplateExpansion) {
        fields = expansion.fields
    }

    /// 直接给字段范围（「插入到当前笔记」时按插入点整体偏移用）
    init(fields: [Range<Int>]) {
        self.fields = fields
    }

    var current: Range<Int>? {
        guard fields.indices.contains(index) else { return nil }
        return fields[index]
    }

    var isActive: Bool { !fields.isEmpty }

    /// 下一个字段（⇧Tab 传 -1）；到头返回 nil = 结束填空
    mutating func advance(_ delta: Int = 1) -> Range<Int>? {
        guard !fields.isEmpty else { return nil }
        visited.insert(index)
        var next = index + delta
        while fields.indices.contains(next), visited.contains(next), fields.count > 1 {
            next += delta
            if next < 0 || next >= fields.count { break }
        }
        guard fields.indices.contains(next) else { return nil }
        index = next
        return fields[index]
    }

    /// 文本发生一处编辑后，同步字段范围：
    /// 编辑点之前的字段不动；包含编辑点的字段按增量伸缩；之后的整体平移。
    mutating func applyEdit(editedRange: Range<Int>, delta: Int) {
        var updated: [Range<Int>] = []
        for range in fields {
            if range.upperBound <= editedRange.lowerBound {
                updated.append(range)                                  // 在编辑点之前
            } else if range.lowerBound >= editedRange.upperBound {
                updated.append((range.lowerBound + delta)..<(range.upperBound + delta))
            } else {
                // 编辑落在该字段内（正常打字）：字段随之伸缩
                let lower = range.lowerBound
                let upper = max(lower, range.upperBound + delta)
                updated.append(lower..<upper)
            }
        }
        fields = updated
    }
}
