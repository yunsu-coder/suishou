import Foundation

/// 编辑器/预览支持的语言家族（按扩展名判定）。
/// 同一家族共用一套扫描规则（注释 / 字符串 / 关键字表），保证「专业文件类型」原生着色。
enum CodeLanguage: String {
    case cFamily      // c / c++ / objective-c / c# / java / kotlin
    case swift
    case rust
    case python
    case go
    case javascript
    case typescript
    case markup       // html / xml / vue / svelte
    case css          // css / scss / less / stylus
    case shell
    case data         // json / yaml / toml / ini / properties
    case sql
    case ruby
    case php
    case lua
    case asm
    case plain

    /// 扩展名 → 语言（小写，不含点）
    static func of(ext: String) -> CodeLanguage {
        switch ext.lowercased() {
        case "c", "h", "cpp", "cc", "cxx", "c++", "hpp", "hh", "hxx", "mpp", "ipp",
             "m", "mm", "cs", "java", "kt", "kts":
            return .cFamily
        case "swift": return .swift
        case "rs": return .rust
        case "py", "pyw", "pyi": return .python
        case "go": return .go
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx", "mts", "cts": return .typescript
        case "html", "htm", "xhtml", "xml", "svg", "vue", "svelte", "xib", "storyboard", "plist":
            return .markup
        case "css", "scss", "sass", "less", "styl": return .css
        case "sh", "bash", "zsh", "fish", "ksh", "ps1", "bat", "cmd": return .shell
        case "json", "jsonc", "json5", "yaml", "yml", "toml", "ini", "cfg", "conf",
             "properties", "env", "gradle", "lock", "lockb", "editorconfig":
            return .data
        case "sql": return .sql
        case "rb", "rake", "gemspec": return .ruby
        case "php", "phtml": return .php
        case "lua": return .lua
        case "asm", "s", "nasm": return .asm
        default: return .plain
        }
    }

    /// 预览侧 highlight.js 的语言 id（vendor/highlight.min.js 里的注册名）
    var highlightJSName: String {
        switch self {
        case .cFamily: return "cpp"
        case .swift: return "swift"
        case .rust: return "rust"
        case .python: return "python"
        case .go: return "go"
        case .javascript: return "javascript"
        case .typescript: return "typescript"
        case .markup: return "xml"
        case .css: return "css"
        case .shell: return "bash"
        case .data: return "json"
        case .sql: return "sql"
        case .ruby: return "ruby"
        case .php: return "php"
        case .lua: return "lua"
        case .asm: return "plaintext"
        case .plain: return "plaintext"
        }
    }

    /// 语言展示名（预览头部 / 状态栏）
    var displayName: String {
        switch self {
        case .cFamily: return "C / C++"
        case .swift: return "Swift"
        case .rust: return "Rust"
        case .python: return "Python"
        case .go: return "Go"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .markup: return "HTML / XML"
        case .css: return "CSS"
        case .shell: return "Shell"
        case .data: return "JSON / YAML"
        case .sql: return "SQL"
        case .ruby: return "Ruby"
        case .php: return "PHP"
        case .lua: return "Lua"
        case .asm: return "Assembly"
        case .plain: return "Text"
        }
    }
}

/// 一种语言的扫描规则（注释符号、字符串形态、关键字表）
struct CodeSyntax {
    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = []
    var lineComments: [String] = ["//"]
    var blockComment: (open: String, close: String)? = ("/*", "*/")
    /// 普通字符串引号（不允许跨行）
    var quotes: [Character] = ["\"", "'"]
    /// 三引号字符串（Python docstring，可跨行）
    var tripleQuotes = false
    /// 反引号字符串（JS 模板串 / Go 原始串，可跨行）
    var backtickString = false
    /// 行首指令：整个指令部分着色（C 的 #include、CSS 的 @media、Python 的 @decorator）
    var lineDirectives: [Character] = []
    /// `key: value` 里的 key（JSON / YAML / CSS 属性）
    var keyBeforeColon = false
    /// 标识符后跟 `(` → 函数名
    var functionCalls = true
    /// 变量前缀（shell/php 的 $、Ruby 的 @/@@）
    var variablePrefixes: [Character] = []
    var markup = false
    var css = false

    static func make(_ build: (inout CodeSyntax) -> Void) -> CodeSyntax {
        var s = CodeSyntax()
        build(&s)
        return s
    }
}

// MARK: - 关键字表

private let cFamilyKeywords: Set<String> = [
    "if", "else", "for", "while", "do", "return", "break", "continue", "switch", "case", "default",
    "struct", "class", "enum", "union", "typedef", "namespace", "using", "template", "typename",
    "new", "delete", "this", "nullptr", "try", "catch", "throw", "throws", "operator", "sizeof",
    "goto", "friend", "explicit", "mutable", "noexcept", "decltype", "alignas", "alignof",
    "static_cast", "dynamic_cast", "const_cast", "reinterpret_cast", "and", "or", "not", "xor",
    "asm", "public", "private", "protected", "virtual", "override", "final", "abstract",
    "synchronized", "volatile", "const", "constexpr", "consteval", "static", "extern", "inline",
    "register", "signed", "unsigned", "auto", "interface", "package", "import", "extends",
    "implements", "instanceof", "super", "async", "await", "yield", "record", "sealed", "when",
    "object", "fun", "val", "suspend", "internal", "sealed", "companion", "init", "deinit",
    "get", "set", "readonly", "partial", "delegate", "event",
]

private let cFamilyTypes: Set<String> = [
    "int", "char", "float", "double", "void", "bool", "short", "long", "wchar_t", "char8_t",
    "char16_t", "char32_t", "size_t", "ssize_t", "ptrdiff_t", "intptr_t", "uintptr_t",
    "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t",
    "u8", "u16", "u32", "u64", "i8", "i16", "i32", "i64", "f32", "f64",
    "string", "wstring", "vector", "map", "set", "unordered_map", "unordered_set", "pair",
    "optional", "variant", "tuple", "array", "deque", "list", "queue", "stack", "bitset",
    "unique_ptr", "shared_ptr", "weak_ptr", "FILE", "fstream", "iostream", "ostream", "istream",
    "stringstream", "ifstream", "ofstream", "uint", "ulong", "ushort", "byte", "sbyte",
    "decimal", "dynamic", "nint", "nuint", "Integer", "Long", "Double", "Boolean", "Object",
]

private let cFamilyConstants: Set<String> = [
    "true", "false", "NULL", "null", "nil", "undefined", "NaN", "EOF", "stdin", "stdout", "stderr",
]

private let pythonKeywords: Set<String> = [
    "def", "class", "return", "if", "elif", "else", "for", "while", "break", "continue", "pass",
    "import", "from", "as", "try", "except", "finally", "raise", "with", "lambda", "yield",
    "global", "nonlocal", "assert", "del", "in", "is", "not", "and", "or", "async", "await",
    "match", "case", "self", "cls",
]

private let pythonTypes: Set<String> = [
    "int", "float", "str", "bool", "bytes", "bytearray", "list", "dict", "set", "frozenset",
    "tuple", "object", "type", "complex", "memoryview", "range", "Any", "Optional", "Union",
    "List", "Dict", "Set", "Tuple", "Callable", "Iterator", "Iterable", "Sequence", "Mapping",
    "Type", "Self", "Literal", "Final",
]

private let goKeywords: Set<String> = [
    "break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough",
    "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range",
    "return", "select", "struct", "switch", "type", "var",
]

private let goTypes: Set<String> = [
    "bool", "byte", "complex64", "complex128", "error", "float32", "float64", "int", "int8",
    "int16", "int32", "int64", "rune", "string", "uint", "uint8", "uint16", "uint32", "uint64",
    "uintptr", "any", "comparable",
]

private let jsKeywords: Set<String> = [
    "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete",
    "do", "else", "export", "extends", "finally", "for", "function", "if", "import", "in",
    "instanceof", "new", "of", "return", "super", "switch", "this", "throw", "try", "typeof",
    "var", "void", "while", "with", "yield", "async", "await", "static", "get", "set", "let",
]

private let tsKeywords: Set<String> = jsKeywords.union([
    "interface", "type", "enum", "implements", "namespace", "declare", "readonly", "private",
    "public", "protected", "abstract", "as", "satisfies", "keyof", "infer", "asserts", "is",
    "override", "module", "require", "global", "unique", "accessor",
])

private let tsTypes: Set<String> = [
    "any", "boolean", "number", "string", "symbol", "void", "never", "unknown", "object",
    "bigint", "Array", "Promise", "Record", "Partial", "Readonly", "Pick", "Omit", "Date",
    "Error", "Map", "Set", "RegExp", "Function", "JSON",
]

private let jsConstants: Set<String> = ["true", "false", "null", "undefined", "NaN", "Infinity"]

private let shellKeywords: Set<String> = [
    "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
    "function", "in", "return", "break", "continue", "local", "export", "readonly", "declare",
    "set", "unset", "source", "alias", "exit", "test", "trap", "shift", "eval", "exec",
    "echo", "printf", "read", "cd", "pwd", "sudo", "which", "type", "command", "let",
]

private let sqlKeywords: Set<String> = [
    "select", "from", "where", "insert", "into", "update", "delete", "create", "drop", "alter",
    "table", "index", "view", "trigger", "procedure", "join", "left", "right", "inner", "outer",
    "full", "cross", "on", "group", "by", "order", "having", "limit", "offset", "union", "all",
    "distinct", "as", "and", "or", "not", "null", "is", "in", "exists", "between", "like",
    "case", "when", "then", "else", "end", "values", "set", "primary", "key", "foreign",
    "references", "default", "unique", "constraint", "begin", "commit", "rollback", "transaction",
    "grant", "revoke", "if", "exists", "count", "sum", "avg", "min", "max", "asc", "desc",
]

private let rubyKeywords: Set<String> = [
    "def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until", "for",
    "in", "do", "return", "yield", "break", "next", "redo", "retry", "begin", "rescue",
    "ensure", "raise", "require", "require_relative", "include", "extend", "prepend",
    "attr_accessor", "attr_reader", "attr_writer", "self", "then", "case", "when", "lambda",
    "proc", "and", "or", "not", "defined?", "alias", "module_function", "private", "public",
    "protected", "super", "block_given?",
]

private let phpKeywords: Set<String> = [
    "function", "class", "interface", "trait", "extends", "implements", "public", "private",
    "protected", "static", "const", "abstract", "final", "if", "else", "elseif", "endif",
    "for", "foreach", "endforeach", "while", "do", "switch", "case", "default", "break",
    "continue", "return", "echo", "print", "new", "clone", "try", "catch", "finally", "throw",
    "namespace", "use", "as", "global", "isset", "unset", "empty", "list", "array", "match",
    "fn", "yield", "and", "or", "xor", "instanceof", "require", "require_once", "include",
    "include_once", "declare", "enddeclare",
]

private let luaKeywords: Set<String> = [
    "function", "end", "local", "if", "then", "else", "elseif", "for", "while", "repeat",
    "until", "do", "return", "break", "goto", "in", "and", "or", "not", "require", "self",
]

private let luaConstants: Set<String> = ["nil", "true", "false", "_G", "_ENV"]

private let asmKeywords: Set<String> = [
    "mov", "push", "pop", "call", "ret", "jmp", "je", "jne", "jz", "jnz", "jg", "jl", "jge",
    "jle", "ja", "jb", "cmp", "test", "add", "sub", "mul", "imul", "div", "idiv", "inc", "dec",
    "lea", "xor", "and", "or", "not", "neg", "shl", "shr", "sar", "rol", "ror", "nop", "int",
    "syscall", "leave", "enter", "movzx", "movsx", "rep", "section", "global", "extern", "db",
    "dw", "dd", "dq", "equ", "byte", "word", "dword", "qword", "ptr", "offset", "align",
]

private let swiftKeywords: Set<String> = [
    "func", "var", "let", "class", "struct", "enum", "protocol", "extension", "init", "deinit",
    "guard", "if", "else", "switch", "case", "default", "for", "while", "repeat", "return",
    "break", "continue", "throw", "throws", "rethrows", "try", "catch", "defer", "do", "import",
    "typealias", "associatedtype", "where", "as", "is", "in", "self", "super", "static", "final",
    "override", "open", "public", "private", "fileprivate", "internal", "lazy", "weak",
    "unowned", "mutating", "nonmutating", "convenience", "required", "subscript", "operator",
    "precedencegroup", "async", "await", "actor", "some", "any", "indirect", "inout", "borrowing",
    "consuming", "package",
]

private let swiftTypes: Set<String> = [
    "Int", "Int8", "Int16", "Int32", "Int64", "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
    "Double", "Float", "String", "Bool", "Character", "Array", "Dictionary", "Set", "Optional",
    "Any", "AnyObject", "Result", "Error", "Void", "Self", "Never", "CGFloat", "URL", "Date",
]

private let rustKeywords: Set<String> = [
    "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "for", "while",
    "loop", "match", "if", "else", "return", "break", "continue", "use", "mod", "pub", "crate",
    "super", "self", "Self", "as", "in", "where", "move", "ref", "dyn", "async", "await",
    "unsafe", "extern", "type", "box", "union", "macro", "yield", "try",
]

private let rustTypes: Set<String> = [
    "i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize",
    "f32", "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box", "Rc",
    "Arc", "RefCell", "Cell", "HashMap", "HashSet", "BTreeMap", "BTreeSet", "VecDeque", "Cow",
    "PathBuf", "Path", "Duration", "Ordering",
]

extension CodeLanguage {
    var syntax: CodeSyntax {
        switch self {
        case .cFamily:
            return .make {
                $0.keywords = cFamilyKeywords
                $0.types = cFamilyTypes
                $0.constants = cFamilyConstants
                $0.lineDirectives = ["#"]
            }
        case .swift:
            return .make {
                $0.keywords = swiftKeywords
                $0.types = swiftTypes
                $0.constants = ["true", "false", "nil"]
                $0.lineDirectives = ["#"]
            }
        case .rust:
            return .make {
                $0.keywords = rustKeywords
                $0.types = rustTypes
                $0.constants = ["true", "false", "None", "Some", "Ok", "Err"]
            }
        case .python:
            return .make {
                $0.keywords = pythonKeywords
                $0.types = pythonTypes
                $0.constants = ["True", "False", "None", "NotImplemented", "Ellipsis", "__name__"]
                $0.lineComments = ["#"]
                $0.blockComment = nil
                $0.tripleQuotes = true
                $0.lineDirectives = ["@"]
            }
        case .go:
            return .make {
                $0.keywords = goKeywords
                $0.types = goTypes
                $0.constants = ["true", "false", "nil", "iota"]
                $0.quotes = ["\"", "'"]
                $0.backtickString = true
            }
        case .javascript:
            return .make {
                $0.keywords = jsKeywords
                $0.types = ["Array", "Promise", "Map", "Set", "Date", "RegExp", "Error", "JSON", "Object", "Function"]
                $0.constants = jsConstants
                $0.backtickString = true
                $0.variablePrefixes = ["$", "_"]
            }
        case .typescript:
            return .make {
                $0.keywords = tsKeywords
                $0.types = tsTypes
                $0.constants = jsConstants
                $0.backtickString = true
                $0.variablePrefixes = ["$", "_"]
            }
        case .markup:
            return .make {
                $0.markup = true
                $0.lineComments = []
                $0.blockComment = ("<!--", "-->")
                $0.functionCalls = false
            }
        case .css:
            return .make {
                $0.css = true
                $0.lineComments = ["//"]          // scss / less / stylus
                $0.blockComment = ("/*", "*/")
                $0.quotes = ["\"", "'"]
                $0.functionCalls = false
            }
        case .shell:
            return .make {
                $0.keywords = shellKeywords
                $0.constants = ["true", "false"]
                $0.lineComments = ["#"]
                $0.blockComment = nil
                $0.variablePrefixes = ["$"]
                $0.functionCalls = false
            }
        case .data:
            return .make {
                $0.keywords = []
                $0.constants = ["true", "false", "null", "~", "yes", "no", "on", "off"]
                $0.lineComments = ["//", "#"]
                $0.blockComment = nil
                $0.quotes = ["\"", "'"]
                $0.keyBeforeColon = true
                $0.functionCalls = false
            }
        case .sql:
            return .make {
                $0.keywords = sqlKeywords
                $0.types = ["int", "integer", "bigint", "smallint", "decimal", "numeric", "real",
                            "float", "double", "char", "varchar", "text", "blob", "date", "time",
                            "datetime", "timestamp", "boolean", "uuid", "json", "jsonb", "serial"]
                $0.constants = ["null", "true", "false"]
                $0.lineComments = ["--"]
                $0.quotes = ["'", "\""]
            }
        case .ruby:
            return .make {
                $0.keywords = rubyKeywords
                $0.types = ["String", "Integer", "Float", "Array", "Hash", "Symbol", "Range",
                            "Struct", "Numeric", "Kernel", "Object", "Class", "Module", "Time"]
                $0.constants = ["true", "false", "nil", "__FILE__", "__LINE__"]
                $0.lineComments = ["#"]
                $0.blockComment = nil
                $0.variablePrefixes = ["@", "$"]
                $0.functionCalls = false
            }
        case .php:
            return .make {
                $0.keywords = phpKeywords
                $0.types = ["int", "float", "string", "bool", "array", "object", "callable",
                            "iterable", "mixed", "void", "null", "self", "static", "parent"]
                $0.constants = ["true", "false", "null", "TRUE", "FALSE", "NULL"]
                $0.lineComments = ["//", "#"]
                $0.variablePrefixes = ["$"]
                $0.lineDirectives = ["#"]
            }
        case .lua:
            return .make {
                $0.keywords = luaKeywords
                $0.constants = luaConstants
                $0.lineComments = ["--"]
                $0.blockComment = ("--[[", "]]")
                $0.functionCalls = false
            }
        case .asm:
            return .make {
                $0.keywords = asmKeywords
                $0.constants = []
                $0.lineComments = [";", "//"]
                $0.functionCalls = false
            }
        case .plain:
            return .make {
                $0.keywords = []
                $0.types = []
                $0.constants = []
                $0.lineComments = []
                $0.blockComment = nil
                $0.functionCalls = false
            }
        }
    }
}
