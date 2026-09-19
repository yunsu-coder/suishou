import XCTest
@testable import MarkNote

/// 模板插件：变量替换、字段定位、填空模式的范围同步、模板包质量门槛。
final class NoteTemplateTests: XCTestCase {

    /// 固定日期（2026-09-19 周六 10:30，本地时区），保证断言稳定
    private let fixedDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 19; c.hour = 10; c.minute = 30
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    private func journal(now: Date? = nil) -> NoteTemplate {
        NoteTemplate(id: "tpl-journal",
                     name: "日记 · 结构化", nameEn: "Journal", icon: "book.closed",
                     category: "日记", desc: "", descEn: nil,
                     body: "---\ndate: {{date}}\nweekday: {{weekday}}\n---\n\n# {{date}} {{weekday}}\n\n"
                           + "- [ ] <#第一件:值得记住的小事#>\n- [ ] <#第二件#>\n\n进度 :: 0/2\n",
                     bodyEn: nil, fileName: "{{date}}", folder: "日记")
    }

    // MARK: - 变量与字段

    func testExpansionFillsVariablesAndFindsFields() {
        let ctx = TemplateContext(title: "日记", now: fixedDate)
        let out = NoteTemplateEngine.expand(journal(), context: ctx)
        XCTAssertFalse(out.text.contains("{{"), "变量都要被替换掉：\(out.text)")
        XCTAssertFalse(out.text.contains("<#"), "字段标记不该留在正文里")
        XCTAssertTrue(out.text.contains("# 2026-09-19 周六"), "日期与星期自动填：\(out.text.prefix(60))")
        XCTAssertEqual(out.fields.count, 2)
        // 字段范围要正好圈住默认值/字段名
        let ns = out.text as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: out.fields[0].lowerBound,
                                                  length: out.fields[0].count)),
                       "值得记住的小事")
        XCTAssertEqual(ns.substring(with: NSRange(location: out.fields[1].lowerBound,
                                                  length: out.fields[1].count)),
                       "第二件", "没写默认值时用字段名当占位")
    }

    func testTomorrowNextWeekAndCursor() {
        let ctx = TemplateContext(title: "", now: fixedDate)
        let tpl = NoteTemplate(id: "x", name: "x", nameEn: nil, icon: "doc", category: "x",
                               desc: "", descEn: nil,
                               body: "due {{tomorrow}} · next {{next_week}} · end{{cursor}}\n",
                               bodyEn: nil, fileName: nil, folder: nil)
        let out = NoteTemplateEngine.expand(tpl, context: ctx)
        XCTAssertTrue(out.text.contains("due 2026-09-20"), out.text)
        XCTAssertTrue(out.text.contains("next 2026-09-26"), out.text)
        XCTAssertEqual(out.cursor, out.text.count - 1, "{{cursor}} 落在文末")
    }

    func testUnknownVariableIsDroppedNotLeftInText() {
        let tpl = NoteTemplate(id: "x", name: "x", nameEn: nil, icon: "doc", category: "x",
                               desc: "", descEn: nil, body: "a{{nope}}b{{date}}", bodyEn: nil,
                               fileName: nil, folder: nil)
        let out = NoteTemplateEngine.expand(tpl, context: TemplateContext(title: "", now: Date()))
        XCTAssertFalse(out.text.contains("{{"), out.text)
    }

    func testUnknownVariablesAreDetectedForAudit() {
        XCTAssertEqual(NoteTemplateEngine.variables(in: "{{date}} {{weekday}} {{typo}}"),
                       ["date", "weekday", "typo"])
        let unknown = NoteTemplateEngine.variables(in: "{{typo}}")
            .subtracting(NoteTemplateEngine.knownVariables)
        XCTAssertEqual(unknown, ["typo"])
    }

    func testFileNameRuleUsesVariablesAndDropsFields() {
        let ctx = TemplateContext(title: "x", now: fixedDate)
        XCTAssertEqual(NoteTemplateEngine.fileName(journal(), context: ctx), "2026-09-19")
        var t = journal()
        t = NoteTemplate(id: t.id, name: t.name, nameEn: nil, icon: t.icon, category: t.category,
                         desc: "", descEn: nil, body: t.body, bodyEn: nil,
                         fileName: "{{date}} <#课程:线代#>", folder: nil)
        XCTAssertEqual(NoteTemplateEngine.fileName(t, context: ctx), "2026-09-19 线代")
    }

    // MARK: - 填空模式（Tab 跳字段 + 编辑同步）

    func testFillPlanAdvancesAndVisitsEachFieldOnce() {
        let out = NoteTemplateEngine.expand(journal(), context: TemplateContext(title: ""))
        var plan = TemplateFillPlan(expansion: out)
        XCTAssertEqual(plan.current?.count, 7, "默认选中第一个字段（默认值「值得记住的小事」7 个字）")
        XCTAssertNotNil(plan.advance(1))
        XCTAssertNil(plan.advance(1), "走到最后一个字段之后再 Tab = 结束填空")
    }

    func testFillPlanShiftsRangesWhenTyping() {
        let out = NoteTemplateEngine.expand(journal(), context: TemplateContext(title: ""))
        var plan = TemplateFillPlan(expansion: out)
        let first = try? XCTUnwrap(plan.current)
        let second = try? XCTUnwrap(plan.advance(1))
        // 在第一个字段里多打 3 个字：第二个字段应整体右移 3
        plan.applyEdit(editedRange: (first!.upperBound)..<(first!.upperBound), delta: 3)
        XCTAssertEqual(plan.current?.lowerBound, second!.lowerBound + 3)
        XCTAssertEqual(plan.current?.count, second!.count, "字段长度不变")
    }

    func testFillPlanShrinksCurrentFieldWhenDeleting() {
        let out = NoteTemplateEngine.expand(journal(), context: TemplateContext(title: ""))
        var plan = TemplateFillPlan(expansion: out)
        let first = plan.current!
        // 删掉第一个字段里的 2 个字
        plan.applyEdit(editedRange: (first.lowerBound + 2)..<(first.lowerBound + 4), delta: -2)
        XCTAssertEqual(plan.current?.count, first.count - 2)
    }

    // MARK: - 工作台落盘

    @MainActor
    func testCreateNoteFromTemplateWritesIntoFolder() throws {
        let (store, dir) = try TestEnv.makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tpl = journal()
        let id = try XCTUnwrap(store.createNoteFromTemplate(
            tpl, context: TemplateContext(title: "日记", now: fixedDate)))
        XCTAssertEqual(id, "日记/2026-09-19.md")
        let text = try String(contentsOf: dir.appendingPathComponent(id), encoding: .utf8)
        XCTAssertTrue(text.contains("date: 2026-09-19"), text)
        XCTAssertTrue(text.contains("# 2026-09-19 周六"), text)
        // 填空计划登记到了这篇笔记上（编辑器装载后会取走）
        XCTAssertNotNil(store.consumePendingFill(for: id))
        XCTAssertNil(store.consumePendingFill(for: id), "取过一次就清掉，避免重复进填空")
    }

    // MARK: - 市场模板包

    /// 三个模板包都要能加载，且通过质量门槛（变量白名单、文件名规则、动态内容）
    @MainActor
    func testMarketTemplatePackagesLoad() throws {
        let market = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("plugins-market")
        let expected = ["template-journal", "template-todo", "template-class"]
        let pm = PluginManager.shared
        for name in expected {
            let src = market.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: src.path), "缺模板包：\(name)")
            let (_, temp) = try TestEnv.makeStore()
            defer { try? FileManager.default.removeItem(at: temp) }
            let dest = temp.appendingPathComponent(".plugins/\(name)")
            try FileManager.default.createDirectory(at: dest.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: src, to: dest)
            UserDefaults.standard.set(true, forKey: "pluginEnabled.\(name)")
            defer { UserDefaults.standard.removeObject(forKey: "pluginEnabled.\(name)") }
            pm.scan(workspaceDir: temp)
            XCTAssertTrue(pm.templateIssues(for: name).isEmpty,
                          "\(name) 未过质量门槛：\(pm.templateIssues(for: name))")
            let templates = pm.allTemplates().filter { $0.id.contains(name) }
            XCTAssertFalse(templates.isEmpty, "\(name) 应该注册出模板")
            XCTAssertTrue(templates.allSatisfy { !$0.category.isEmpty }, "模板要有分类")
            XCTAssertTrue(templates.allSatisfy { $0.displayBody.contains("{{") || $0.displayBody.contains("<#") },
                          "模板至少要有一处动态内容")
        }
    }
}
