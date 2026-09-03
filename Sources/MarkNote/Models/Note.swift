import Foundation

/// 文件模型 —— 独立数据源（本机 JSON 直存，目录即库，可整体备份/迁移）
/// 文件结构: { id, title, content, category, created, updated }
struct Note: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var content: String
    /// 文件夹（分类）id（'' = 根目录）
    var category: String
    var created: String
    var updated: String

    init(id: String = NotesStore.newID(),
         title: String = "",
         content: String = "",
         category: String = "",
         created: String = NotesStore.isoNow(),
         updated: String = NotesStore.isoNow()) {
        self.id = id
        self.title = title
        self.content = content
        self.category = category
        self.created = created
        self.updated = updated
    }

    /// 宽容解码：旧数据缺字段时给默认值，而不是整个文件打不开
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? NotesStore.newID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? _L("无标题", "Untitled")
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        created = try c.decodeIfPresent(String.self, forKey: .created) ?? NotesStore.isoNow()
        updated = try c.decodeIfPresent(String.self, forKey: .updated) ?? NotesStore.isoNow()
    }
}

/// 文件夹（分类）定义 —— 独立数据源格式
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
}
