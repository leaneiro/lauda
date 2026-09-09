import Foundation

/// Minimal, dependency-free syntax highlighter for fenced code blocks in the
/// preview and exports. Scanner-based and deliberately modest: comments,
/// strings, numbers and keywords — enough color to read code comfortably.
enum CodeHighlighter {
    struct Language {
        var lineComments: [String] = []
        var blockComments: [(open: String, close: String)] = []
        /// Ordered longest-first so `"""` wins over `"`.
        var stringDelimiters: [(open: String, close: String, escapes: Bool)] = []
        var keywords: Set<String> = []
    }

    /// Returns span-annotated escaped HTML, or nil for unknown languages
    /// (caller falls back to plain escaping).
    static func highlight(_ code: String, language: String?) -> String? {
        guard let language,
              let key = language.split(separator: " ").first?.lowercased(),
              let spec = languages[key] else { return nil }
        return tokenize(code, spec: spec)
    }

    // MARK: - Tokenizer

    private static func tokenize(_ code: String, spec: Language) -> String {
        let chars = Array(code)
        var html = ""
        var plain = ""
        var i = 0

        func matches(_ delimiter: String, at index: Int) -> Bool {
            let d = Array(delimiter)
            guard index + d.count <= chars.count else { return false }
            return Array(chars[index..<index + d.count]) == d
        }
        func flushPlain() {
            guard !plain.isEmpty else { return }
            html += stylePlain(plain, keywords: spec.keywords)
            plain = ""
        }
        func span(_ cssClass: String, _ text: String) -> String {
            "<span class=\"\(cssClass)\">\(HTMLRenderer.escape(text))</span>"
        }

        outer: while i < chars.count {
            for prefix in spec.lineComments where matches(prefix, at: i) {
                flushPlain()
                var j = i
                while j < chars.count, chars[j] != "\n" { j += 1 }
                html += span("hl-com", String(chars[i..<j]))
                i = j
                continue outer
            }
            for block in spec.blockComments where matches(block.open, at: i) {
                flushPlain()
                var j = i + block.open.count
                while j < chars.count, !matches(block.close, at: j) { j += 1 }
                let end = min(j + block.close.count, chars.count)
                html += span("hl-com", String(chars[i..<end]))
                i = end
                continue outer
            }
            for string in spec.stringDelimiters where matches(string.open, at: i) {
                var j = i + string.open.count
                while j < chars.count {
                    if string.escapes, chars[j] == "\\" { j += 2; continue }
                    if matches(string.close, at: j) { j += string.close.count; break }
                    j += 1
                }
                let end = min(j, chars.count)
                flushPlain()
                html += span("hl-str", String(chars[i..<end]))
                i = end
                continue outer
            }
            plain.append(chars[i])
            i += 1
        }
        flushPlain()
        return html
    }

    private static let identifierRegex = try! NSRegularExpression(pattern: "[A-Za-z_][A-Za-z0-9_]*")
    private static let numberRegex = try! NSRegularExpression(pattern: #"\b\d[\d_]*(?:\.[\d_]+)?\b"#)

    /// Escapes a plain segment, then wraps keywords and numeric literals.
    private static func stylePlain(_ text: String, keywords: Set<String>) -> String {
        let escaped = HTMLRenderer.escape(text) as NSString
        var result = ""
        var cursor = 0
        identifierRegex.enumerateMatches(
            in: escaped as String,
            range: NSRange(location: 0, length: escaped.length)
        ) { match, _, _ in
            guard let match else { return }
            let word = escaped.substring(with: match.range)
            guard keywords.contains(word) else { return }
            result += wrapNumbers(escaped.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            result += "<span class=\"hl-kw\">\(word)</span>"
            cursor = NSMaxRange(match.range)
        }
        result += wrapNumbers(escaped.substring(from: cursor))
        return result
    }

    private static func wrapNumbers(_ escapedText: String) -> String {
        numberRegex.stringByReplacingMatches(
            in: escapedText,
            range: NSRange(location: 0, length: (escapedText as NSString).length),
            withTemplate: "<span class=\"hl-num\">$0</span>"
        )
    }

    // MARK: - Language table

    private static let languages: [String: Language] = {
        let cStrings: [(String, String, Bool)] = [("\"", "\"", true), ("'", "'", true)]
        let cComments: [(String, String)] = [("/*", "*/")]

        let swift = Language(
            lineComments: ["//"], blockComments: cComments,
            stringDelimiters: [("\"\"\"", "\"\"\"", true), ("\"", "\"", true)],
            keywords: ["let", "var", "func", "class", "struct", "enum", "protocol", "extension",
                       "import", "if", "else", "guard", "switch", "case", "default", "for", "while",
                       "repeat", "in", "return", "break", "continue", "where", "as", "is", "try",
                       "catch", "throw", "throws", "rethrows", "do", "defer", "init", "deinit",
                       "self", "Self", "super", "nil", "true", "false", "static", "final", "public",
                       "private", "fileprivate", "internal", "open", "override", "mutating", "lazy",
                       "weak", "unowned", "typealias", "associatedtype", "some", "any", "await",
                       "async", "actor", "convenience", "required", "indirect", "subscript", "get",
                       "set", "willSet", "didSet", "inout"]
        )
        let kotlin = Language(
            lineComments: ["//"], blockComments: cComments,
            stringDelimiters: [("\"\"\"", "\"\"\"", true), ("\"", "\"", true), ("'", "'", true)],
            keywords: ["fun", "val", "var", "class", "object", "interface", "enum", "data", "sealed",
                       "if", "else", "when", "for", "while", "do", "return", "break", "continue",
                       "in", "is", "as", "try", "catch", "finally", "throw", "import", "package",
                       "null", "true", "false", "this", "super", "companion", "init", "constructor",
                       "override", "open", "abstract", "final", "private", "public", "protected",
                       "internal", "lateinit", "by", "lazy", "suspend", "inline", "reified", "out",
                       "vararg", "typealias", "where"]
        )
        let java = Language(
            lineComments: ["//"], blockComments: cComments, stringDelimiters: cStrings,
            keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char",
                       "class", "const", "continue", "default", "do", "double", "else", "enum",
                       "extends", "final", "finally", "float", "for", "if", "implements", "import",
                       "instanceof", "int", "interface", "long", "native", "new", "package",
                       "private", "protected", "public", "record", "return", "short", "static",
                       "super", "switch", "synchronized", "this", "throw", "throws", "try", "var",
                       "void", "volatile", "while", "null", "true", "false", "sealed", "permits"]
        )
        let javascript = Language(
            lineComments: ["//"], blockComments: cComments,
            stringDelimiters: [("`", "`", true), ("\"", "\"", true), ("'", "'", true)],
            keywords: ["function", "var", "let", "const", "class", "extends", "implements",
                       "interface", "if", "else", "switch", "case", "default", "for", "while", "do",
                       "return", "break", "continue", "new", "delete", "typeof", "instanceof", "in",
                       "of", "try", "catch", "finally", "throw", "import", "export", "from", "as",
                       "async", "await", "yield", "this", "super", "null", "undefined", "true",
                       "false", "static", "get", "set", "void", "enum", "type", "declare",
                       "readonly", "namespace"]
        )
        let python = Language(
            lineComments: ["#"],
            stringDelimiters: [("\"\"\"", "\"\"\"", true), ("'''", "'''", true),
                               ("\"", "\"", true), ("'", "'", true)],
            keywords: ["def", "class", "if", "elif", "else", "for", "while", "in", "is", "not",
                       "and", "or", "return", "yield", "import", "from", "as", "try", "except",
                       "finally", "raise", "with", "lambda", "pass", "break", "continue", "global",
                       "nonlocal", "del", "assert", "async", "await", "None", "True", "False",
                       "self", "match", "case"]
        )
        let go = Language(
            lineComments: ["//"], blockComments: cComments,
            stringDelimiters: [("`", "`", false), ("\"", "\"", true), ("'", "'", true)],
            keywords: ["func", "var", "const", "type", "struct", "interface", "map", "chan", "if",
                       "else", "switch", "case", "default", "for", "range", "return", "break",
                       "continue", "goto", "fallthrough", "defer", "go", "select", "package",
                       "import", "nil", "true", "false", "iota", "make", "new", "len", "cap",
                       "append", "error", "string", "int", "bool", "byte", "rune", "float64"]
        )
        let rust = Language(
            lineComments: ["//"], blockComments: cComments,
            stringDelimiters: [("\"", "\"", true)],
            keywords: ["fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl",
                       "for", "while", "loop", "if", "else", "match", "return", "break", "continue",
                       "in", "as", "use", "mod", "pub", "crate", "self", "Self", "super", "where",
                       "async", "await", "move", "ref", "dyn", "unsafe", "true", "false", "Some",
                       "None", "Ok", "Err", "String", "Vec", "Option", "Result"]
        )
        let c = Language(
            lineComments: ["//"], blockComments: cComments, stringDelimiters: cStrings,
            keywords: ["auto", "break", "case", "char", "const", "continue", "default", "do",
                       "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline",
                       "int", "long", "register", "return", "short", "signed", "sizeof", "static",
                       "struct", "switch", "typedef", "union", "unsigned", "void", "volatile",
                       "while", "NULL", "true", "false", "bool"]
        )
        var cpp = c
        cpp.keywords.formUnion(["class", "namespace", "template", "typename", "public", "private",
                                "protected", "virtual", "override", "new", "delete", "this",
                                "nullptr", "try", "catch", "throw", "using", "constexpr", "auto"])
        let csharp = Language(
            lineComments: ["//"], blockComments: cComments, stringDelimiters: cStrings,
            keywords: ["abstract", "as", "async", "await", "base", "bool", "break", "case", "catch",
                       "class", "const", "continue", "default", "delegate", "do", "double", "else",
                       "enum", "event", "finally", "float", "for", "foreach", "get", "if", "in",
                       "int", "interface", "internal", "is", "lock", "long", "namespace", "new",
                       "null", "object", "out", "override", "private", "protected", "public",
                       "readonly", "record", "return", "sealed", "set", "static", "string",
                       "struct", "switch", "this", "throw", "try", "typeof", "using", "var",
                       "virtual", "void", "while", "true", "false"]
        )
        let ruby = Language(
            lineComments: ["#"], stringDelimiters: cStrings.map { ($0.0, $0.1, $0.2) },
            keywords: ["def", "class", "module", "if", "elsif", "else", "unless", "case", "when",
                       "while", "until", "for", "in", "do", "end", "return", "break", "next",
                       "begin", "rescue", "ensure", "raise", "yield", "self", "nil", "true",
                       "false", "and", "or", "not", "require", "attr_accessor", "puts", "lambda"]
        )
        let php = Language(
            lineComments: ["//", "#"], blockComments: cComments, stringDelimiters: cStrings,
            keywords: ["function", "class", "interface", "trait", "extends", "implements", "public",
                       "private", "protected", "static", "const", "var", "if", "else", "elseif",
                       "switch", "case", "default", "for", "foreach", "while", "do", "return",
                       "break", "continue", "new", "try", "catch", "finally", "throw", "use",
                       "namespace", "echo", "null", "true", "false", "as", "match", "fn"]
        )
        let bash = Language(
            lineComments: ["#"], stringDelimiters: [("\"", "\"", true), ("'", "'", false)],
            keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done",
                       "case", "esac", "function", "in", "echo", "exit", "return", "local",
                       "export", "source", "set", "shift", "read", "true", "false"]
        )
        let sql = Language(
            lineComments: ["--"], blockComments: cComments,
            stringDelimiters: [("'", "'", false)],
            keywords: ["SELECT", "select", "FROM", "from", "WHERE", "where", "INSERT", "insert",
                       "INTO", "into", "VALUES", "values", "UPDATE", "update", "SET", "set",
                       "DELETE", "delete", "CREATE", "create", "TABLE", "table", "ALTER", "alter",
                       "DROP", "drop", "JOIN", "join", "LEFT", "left", "RIGHT", "right", "INNER",
                       "inner", "OUTER", "outer", "ON", "on", "AS", "as", "AND", "and", "OR", "or",
                       "NOT", "not", "NULL", "null", "ORDER", "order", "BY", "by", "GROUP", "group",
                       "HAVING", "having", "LIMIT", "limit", "DISTINCT", "distinct", "INDEX",
                       "index", "PRIMARY", "primary", "KEY", "key", "FOREIGN", "foreign"]
        )
        let json = Language(
            stringDelimiters: [("\"", "\"", true)],
            keywords: ["true", "false", "null"]
        )
        let yaml = Language(
            lineComments: ["#"], stringDelimiters: [("\"", "\"", true), ("'", "'", false)],
            keywords: ["true", "false", "null", "yes", "no"]
        )
        let css = Language(
            blockComments: cComments, stringDelimiters: cStrings,
            keywords: ["important", "inherit", "initial", "unset", "auto", "none", "var", "calc",
                       "min", "max", "clamp", "media", "root", "hover", "focus", "active"]
        )

        var table: [String: Language] = [:]
        func register(_ spec: Language, _ names: String...) {
            for name in names { table[name] = spec }
        }
        register(swift, "swift")
        register(kotlin, "kotlin", "kt", "kts")
        register(java, "java")
        register(javascript, "javascript", "js", "jsx", "typescript", "ts", "tsx")
        register(python, "python", "py")
        register(go, "go", "golang")
        register(rust, "rust", "rs")
        register(c, "c", "h", "objc", "objective-c")
        register(cpp, "cpp", "c++", "cc", "hpp")
        register(csharp, "csharp", "cs", "c#")
        register(ruby, "ruby", "rb")
        register(php, "php")
        register(bash, "bash", "sh", "shell", "zsh", "console")
        register(sql, "sql")
        register(json, "json")
        register(yaml, "yaml", "yml")
        register(css, "css", "scss")
        return table
    }()
}
