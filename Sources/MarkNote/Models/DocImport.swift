import Foundation
import PDFKit

/// 办公 / 富文本 / 表格 → Markdown 导入。
///
/// · doc / docx / rtf / odt：系统 `textutil` 转 HTML → `HTMLToMarkdown`（标题层级、列表、粗体、表格都保住）；
/// · pdf：PDFKit 按页抽正文；
/// · csv / tsv：直接转 Markdown 表格；
/// · xlsx：解包（unzip）+ 解析第一张工作表 → Markdown 表格。
/// 转换结果随后走与 .md 完全相同的导入管线（标题提升 / 换行治理 / 重名加序号），保证"开箱可用"。
enum DocImport {

    static func handles(_ ext: String) -> Bool {
        richExts.contains(ext) || ["pdf", "csv", "tsv", "xlsx"].contains(ext)
    }

    static let richExts: Set<String> = ["doc", "docx", "rtf", "rtfd", "odt", "webarchive"]

    static func markdown(from url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if richExts.contains(ext) { return fromRichText(url) }
        if ext == "pdf" { return fromPDF(url) }
        if ext == "csv" { return table(fromCSV: TextDecoding.string(contentsOf: url) ?? "", delimiter: ",") }
        if ext == "tsv" { return table(fromCSV: TextDecoding.string(contentsOf: url) ?? "", delimiter: "\t") }
        if ext == "xlsx" { return fromXLSX(url) }
        return nil
    }

    // MARK: - 富文本（doc / docx / rtf / odt）→ textutil → HTML → Markdown

    private static func fromRichText(_ url: URL) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        p.arguments = ["-convert", "html", "-stdout", url.path]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch { return nil }
        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        guard p.terminationStatus == 0, !data.isEmpty,
              let html = String(data: data, encoding: .utf8) else { return nil }
        let md = normalize(HTMLToMarkdown.convert(html))
        return md.isEmpty ? nil : md
    }

    // MARK: - PDF

    private static func fromPDF(_ url: URL) -> String? {
        guard let doc = PDFDocument(url: url) else { return nil }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            if let t = doc.page(at: i)?.string, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pages.append(t)
            }
        }
        guard !pages.isEmpty else { return nil }
        return normalize(pages.joined(separator: "\n\n"))
    }

    // MARK: - CSV / TSV / XLSX → Markdown 表格

    static func table(fromCSV text: String, delimiter: Character) -> String? {
        tableFromRows(parseCSV(text, delimiter: delimiter))
    }

    private static func fromXLSX(_ url: URL) -> String? {
        guard let sharedData = unzipEntry(url, "xl/sharedStrings.xml"),
              let sheetData = unzipEntry(url, "xl/worksheets/sheet1.xml") else { return nil }
        let shared = SharedStringsParser.parse(sharedData)
        let rows = SheetParser.parse(sheetData, shared: shared)
        return tableFromRows(rows)
    }

    private static func tableFromRows(_ rows: [[String]]) -> String? {
        let clean = rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = clean.first, !header.isEmpty else { return nil }
        let width = clean.map(\.count).max() ?? header.count
        func padded(_ row: [String]) -> [String] {
            row + Array(repeating: "", count: max(0, width - row.count))
        }
        var md = "| " + padded(header).map(escapeCell).joined(separator: " | ") + " |\n"
        md += "| " + Array(repeating: "---", count: width).joined(separator: " | ") + " |\n"
        for row in clean.dropFirst() {
            md += "| " + padded(row).map(escapeCell).joined(separator: " | ") + " |\n"
        }
        return md.isEmpty ? nil : md
    }

    private static func escapeCell(_ s: String) -> String {
        s.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    /// 极简 CSV 解析：引号包裹 + `""` 转义 + 换行折行
    private static func parseCSV(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        cell.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    cell.append(c)
                }
            } else if c == "\"" {
                inQuotes = true
            } else if c == delimiter {
                row.append(cell)
                cell = ""
            } else if c == "\n" {
                row.append(cell)
                cell = ""
                rows.append(row)
                row = []
            } else if c != "\r" {
                cell.append(c)
            }
            i += 1
        }
        if !cell.isEmpty || !row.isEmpty {
            row.append(cell)
            rows.append(row)
        }
        return rows
    }

    // MARK: - xlsx 解包 + XML

    private static func unzipEntry(_ zip: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", zip.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        p.waitUntilExit()
        return p.terminationStatus == 0 && !data.isEmpty ? data : nil
    }

    /// xl/sharedStrings.xml：`<si>` 一段共享字符串（含 `<r><t>` 富文本分段）
    private final class SharedStringsParser: NSObject, XMLParserDelegate {
        static func parse(_ data: Data) -> [String] {
            let p = SharedStringsParser()
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.strings
        }
        private var strings: [String] = []
        private var current: String?
        private var inT = false

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            if elementName == "si" { current = "" }
            if elementName == "t" { inT = true }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inT { current? += string }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if elementName == "t" { inT = false }
            if elementName == "si" {
                strings.append(current ?? "")
                current = nil
            }
        }
    }

    /// xl/worksheets/sheet1.xml：行 → 单元格（`t="s"` 共享串 / `t="inlineStr"` 内联 / 其余取原文）
    private final class SheetParser: NSObject, XMLParserDelegate {
        static func parse(_ data: Data, shared: [String]) -> [[String]] {
            let p = SheetParser(shared: shared)
            let parser = XMLParser(data: data)
            parser.delegate = p
            parser.parse()
            return p.rows
        }
        private let shared: [String]
        private var rows: [[String]] = []
        private var row: [String] = []
        private var cellType: String?
        private var cellColumn: Int?
        private var value: String?
        private var inText = false

        init(shared: [String]) {
            self.shared = shared
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String]) {
            switch elementName {
            case "row":
                row = []
            case "c":
                cellType = attributeDict["t"]
                cellColumn = Self.columnIndex(attributeDict["r"])
                value = nil
            case "v", "t":
                inText = true
            default:
                break
            }
        }
        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { value = (value ?? "") + string }
        }
        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            switch elementName {
            case "v", "t":
                inText = false
            case "c":
                let text: String
                if cellType == "s", let idx = Int((value ?? "").trimmingCharacters(in: .whitespaces)),
                   shared.indices.contains(idx) {
                    text = shared[idx]
                } else {
                    text = value ?? ""
                }
                let column = cellColumn ?? row.count
                if row.count < column {
                    row += Array(repeating: "", count: column - row.count)
                }
                if row.count == column {
                    row.append(text)
                } else {
                    row[column] = text
                }
                cellType = nil
                cellColumn = nil
                value = nil
            case "row":
                rows.append(row)
            default:
                break
            }
        }

        /// "BC12" → 列号 54（A=0）
        private static func columnIndex(_ ref: String?) -> Int? {
            guard let ref else { return nil }
            var acc = 0
            var found = false
            for ch in ref.uppercased() {
                guard let ascii = ch.asciiValue, ascii >= 65, ascii <= 90 else { break }
                acc = acc * 26 + Int(ascii - 64)
                found = true
            }
            return found ? acc - 1 : nil
        }
    }

    // MARK: - 清理

    /// 压掉 3 连以上换行、收敛行尾空白 —— 导入后排版不"散"
    private static func normalize(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "\r\n", with: "\n")
        while t.contains("\n\n\n") { t = t.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        t = t.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.replacingOccurrences(of: #"[ \t]+$"#, with: "", options: .regularExpression) }
            .joined(separator: "\n")
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
