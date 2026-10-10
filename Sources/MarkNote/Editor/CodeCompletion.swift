import Foundation

/// 本地代码补全（Tab 补全）：当前文件词表 + 各语言关键字 / 常用 API。
/// 无弹窗、无菜单 —— Tab 接受首选；再按 Tab / ⇧Tab 循环；Esc 取消。
/// clangd 在场时，其语义结果到达后会替换为更"懂代码"的候选项。
enum CodeCompletion {

    /// 光标左侧标识符前缀范围（[A-Za-z_][A-Za-z0-9_]*）
    static func prefixRange(in text: NSString, at caret: Int) -> NSRange {
        let end = min(max(0, caret), text.length)
        var start = end
        while start > 0, isIdentChar(text.character(at: start - 1)) { start -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isIdentChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    /// UTF-16 偏移 → LSP 坐标（0-based line / character）
    static func lspPosition(in text: NSString, at index: Int) -> (line: Int, character: Int) {
        let capped = min(max(0, index), text.length)
        var line = 0
        var i = 0
        while i < capped {
            var lineStart = 0, lineEnd = 0, contentsEnd = 0
            text.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd,
                              for: NSRange(location: i, length: 0))
            if capped < lineEnd {
                i = lineStart
                break
            }
            if capped == lineEnd, contentsEnd == lineEnd {
                i = lineStart   // 文档最后一行的行尾没有换行：停在原地
                break
            }
            i = lineEnd
            line += 1
        }
        return (line, capped - i)
    }

    /// 文档词频（出现次数降序；同频按首次出现；长度 ≥2；不以数字开头）
    static func documentWords(in text: String) -> [(word: String, count: Int)] {
        var counts: [String: Int] = [:]
        var firstSeen: [String: Int] = [:]
        var order = 0
        var current = ""
        func flush() {
            defer { current = "" }
            guard current.count >= 2, let f = current.first, f.isLetter || f == "_" else { return }
            counts[current, default: 0] += 1
            if firstSeen[current] == nil {
                firstSeen[current] = order
                order += 1
            }
        }
        for ch in text {
            if ch.isASCII, ch.isLetter || ch.isNumber || ch == "_" {
                current.append(ch)
                if current.count > 64 { flush() }
            } else {
                flush()
            }
        }
        flush()
        return counts.map { (word: $0.key, count: $0.value, seen: firstSeen[$0.key] ?? 0) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.seen < $1.seen }
            .map { (word: $0.word, count: $0.count) }
    }

    /// 候选：语言关键字 / 常用 API 优先，其次是文档词频表；去重、剔除与前缀完全相同的项
    static func candidates(prefix: String, ext: String,
                           documentWords: [(word: String, count: Int)],
                           limit: Int = 60) -> [String] {
        guard !prefix.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        func add(_ word: String) {
            guard word != prefix, word.hasPrefix(prefix), !seen.contains(word) else { return }
            seen.insert(word)
            out.append(word)
        }
        for w in keywordPool(ext) { add(w) }
        for w in documentWords { add(w.word) }
        if out.count > limit { out.removeLast(out.count - limit) }
        return out
    }

    // MARK: - 语言词库（关键字 + 常用标准库标识符；够 Tab 补全用，不追求全量）

    static func keywordPool(_ ext: String) -> [String] {
        switch ext.lowercased() {
        case "c", "h":
            return cKeywords
        case "cc", "cpp", "cxx", "hpp", "hxx", "mm", "m":
            return cppPool
        case "py":
            return pythonPool
        case "js", "jsx", "mjs", "cjs", "ts", "tsx", "vue", "svelte":
            return jsPool
        case "go":
            return goPool
        case "html", "htm", "css", "scss", "less":
            return webPool
        default:
            return []
        }
    }

    private static let cKeywords: [String] = [
        "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue",
        "struct", "union", "enum", "typedef", "static", "const", "extern", "inline", "void",
        "int", "long", "short", "char", "float", "double", "signed", "unsigned", "size_t",
        "sizeof", "include", "define", "ifdef", "ifndef", "endif", "pragma", "goto", "volatile",
        "register", "printf", "scanf", "malloc", "free", "calloc", "realloc", "memcpy", "memset",
        "strlen", "strcmp", "NULL"]

    private static let cppExtras: [String] = [
        "namespace", "using", "template", "typename", "class", "public", "private", "protected",
        "virtual", "override", "final", "constexpr", "noexcept", "auto", "nullptr", "true", "false",
        "new", "delete", "this", "operator", "friend", "explicit", "mutable", "static_cast",
        "dynamic_cast", "reinterpret_cast", "const_cast", "try", "catch", "throw", "std", "cout",
        "cin", "cerr", "endl", "getline", "string", "vector", "map", "set", "queue", "stack",
        "deque", "priority_queue", "unordered_map", "unordered_set", "pair", "make_pair", "tuple",
        "array", "thread", "mutex", "atomic", "function", "bind", "sort", "stable_sort", "reverse",
        "unique", "find", "count", "lower_bound", "upper_bound", "push_back", "pop_back",
        "emplace_back", "resize", "reserve", "begin", "end", "size", "empty", "clear", "insert",
        "erase", "swap", "max", "min", "abs", "sqrt", "pow", "floor", "ceil", "round", "log",
        "exp", "INT_MAX", "INT_MIN", "LLONG_MAX", "LLONG_MIN", "INT64_MAX", "INT64_MIN",
        "M_PI", "eps"]

    /// C++ = 扩展关键字在前，C 关键字补齐（顺序影响同名候选的优先级）
    private static let cppPool: [String] = {
        var out = cppExtras
        for w in cKeywords where !out.contains(w) { out.append(w) }
        return out
    }()

    private static let pythonPool: [String] = [
        "def", "class", "return", "if", "elif", "else", "for", "while", "break", "continue",
        "pass", "import", "from", "as", "with", "try", "except", "finally", "raise", "lambda",
        "yield", "global", "nonlocal", "assert", "del", "in", "is", "not", "and", "or", "None",
        "True", "False", "self", "print", "input", "len", "range", "enumerate", "zip", "map",
        "filter", "sum", "max", "min", "abs", "round", "sorted", "reversed", "list", "dict",
        "set", "tuple", "str", "int", "float", "bool", "bytes", "isinstance", "type", "open",
        "read", "write", "append", "extend", "split", "join", "strip", "replace", "startswith",
        "endswith", "format", "property", "staticmethod", "classmethod"]

    private static let jsPool: [String] = [
        "function", "return", "const", "let", "var", "if", "else", "for", "while", "do",
        "switch", "case", "break", "continue", "class", "extends", "constructor", "import",
        "export", "default", "from", "async", "await", "Promise", "then", "catch", "try",
        "throw", "new", "this", "typeof", "instanceof", "null", "undefined", "true", "false",
        "console", "log", "document", "window", "Array", "Object", "String", "Number", "Boolean",
        "JSON", "Math", "Date", "Map", "Set", "push", "pop", "shift", "unshift", "slice",
        "splice", "map", "filter", "reduce", "forEach", "find", "includes", "join", "split",
        "trim", "toLowerCase", "toUpperCase", "parseInt", "parseFloat", "fetch",
        "addEventListener", "querySelector", "require", "module", "interface", "type", "enum",
        "implements", "readonly", "public", "private", "protected"]

    private static let goPool: [String] = [
        "package", "import", "func", "return", "if", "else", "for", "range", "switch", "case",
        "default", "break", "continue", "goto", "var", "const", "type", "struct", "interface",
        "map", "chan", "go", "defer", "select", "nil", "true", "false", "iota", "int32", "int64",
        "float64", "string", "bool", "byte", "rune", "error", "make", "new", "len", "cap",
        "append", "copy", "delete", "panic", "recover", "fmt", "Println", "Printf", "Sprintf",
        "Errorf", "strings", "strconv", "sort", "sync", "context", "time", "os", "io", "net"]

    private static let webPool: [String] = [
        "div", "span", "class", "id", "style", "href", "src", "alt", "width", "height",
        "margin", "padding", "border", "display", "flex", "grid", "absolute", "relative",
        "fixed", "color", "background", "font-family", "font-size", "font-weight", "line-height",
        "border-radius", "box-shadow", "transition", "transform", "animation", "position",
        "top", "left", "right", "bottom", "max-width", "min-width", "justify-content",
        "align-items", "gap", "cursor", "overflow", "opacity", "z-index", "media", "keyframes",
        "var", "calc", "button", "input", "select", "textarea", "form", "label", "table",
        "thead", "tbody", "tr", "td", "th", "ul", "ol", "li", "header", "footer", "section",
        "article", "nav", "main", "script", "link", "meta"]
}
