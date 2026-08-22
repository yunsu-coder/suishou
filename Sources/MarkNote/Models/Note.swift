import Foundation

/// 笔记模型 —— 与 start 项目 notes/<id>.json 的文件格式完全一致，
/// 可直接读写 start 的 notes 目录，两个应用无缝共存。
/// 文件结构: { id, title, content, workId, chapterOrder, category, created, updated }
struct Note: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    /// start 项目的小说章节归属（独立笔记为空串），保留字段以兼容
    var workId: String
    var chapterOrder: Int
    /// 分类 id（'' = 未分类）
    var category: String
    var created: String
    var updated: String

    init(id: String = NotesStore.newID(),
         title: String = "",
         content: String = "",
         workId: String = "",
         chapterOrder: Int = 0,
         category: String = "",
         created: String = NotesStore.isoNow(),
         updated: String = NotesStore.isoNow()) {
        self.id = id
        self.title = title
        self.content = content
        self.workId = workId
        self.chapterOrder = chapterOrder
        self.category = category
        self.created = created
        self.updated = updated
    }

    /// 宽容解码：旧数据缺字段时给默认值，而不是整个笔记打不开
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? NotesStore.newID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "无标题"
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        workId = try c.decodeIfPresent(String.self, forKey: .workId) ?? ""
        chapterOrder = try c.decodeIfPresent(Int.self, forKey: .chapterOrder) ?? 0
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        created = try c.decodeIfPresent(String.self, forKey: .created) ?? NotesStore.isoNow()
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? NotesStore.isoNow()
    }
}

/// 分类 —— 与 start 项目 notes/.categories.json 的格式一致
struct NoteCategory: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var color: String
    var created: String

    init(id: String = "cat_" + NotesStore.randomHex(5),
         name: String,
         color: String = "#6d8bff",
         created: String = NotesStore.isoNow()) {
        self.id = id
        self.name = name
        self.color = color
        self.created = created
    }
}

/// 侧边栏索引条目 —— 只读文件名 + 摘要，避免加载全文拖慢列表
struct NoteIndexItem: Identifiable, Equatable, Hashable {
    let id: String
    var title: String
    var preview: String
    var created: String
    var updated: String
    var category: String
    var workId: String
    var chapterOrder: Int
}
