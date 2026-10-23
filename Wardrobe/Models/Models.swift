import Foundation
import SwiftData

enum ItemStatus: Int {
    case pending = 0       // 等待抠图
    case failed = 1        // 抠图失败，待分类
    case unclassified = 2  // 抠图完成，待分类
    case classified = 3    // 已进入衣橱
}

@Model
final class ClothingItem {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var statusRaw: Int = ItemStatus.pending.rawValue
    /// 原图只在抠图前和抠图失败时保留，抠图成功后删除（置为空字符串）
    var originalFile: String = ""
    var originalThumb: String?
    var cutoutFile: String?
    var cutoutThumb: String?
    var categoryID: UUID?
    var subcategoryID: UUID?
    var tagIDs: [UUID] = []
    var note: String = ""

    init(originalFile: String) {
        self.originalFile = originalFile
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    var hasCutout: Bool { cutoutFile != nil }

    var hasOriginal: Bool { !originalFile.isEmpty }

    var displayFile: String? { cutoutFile ?? (hasOriginal ? originalFile : nil) }

    var displayThumb: String? { cutoutThumb ?? originalThumb }

    var allFiles: [String?] { [hasOriginal ? originalFile : nil, originalThumb, cutoutFile, cutoutThumb] }

    /// 抠图成功后把原图删掉，节省空间
    func dropOriginal() {
        guard hasCutout, hasOriginal || originalThumb != nil else { return }
        ImageStore.delete([hasOriginal ? originalFile : nil, originalThumb])
        originalFile = ""
        originalThumb = nil
    }
}

/// 分类：parentID 为空是大类，否则是某个大类下的小类
@Model
final class Category {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0
    var parentID: UUID?

    init(name: String, order: Int, parentID: UUID? = nil) {
        self.name = name
        self.order = order
        self.parentID = parentID
    }
}

/// 季节和自定义标签（通勤、约会……）
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var order: Int = 0

    init(name: String, order: Int) {
        self.name = name
        self.order = order
    }
}

@Model
final class OutfitDay {
    @Attribute(.unique) var dayKey: String = ""
    var date: Date = Date()
    var itemIDs: [UUID] = []
    var collageFile: String?
    var collageThumb: String?

    init(date: Date) {
        self.date = DayKey.calendar.startOfDay(for: date)
        self.dayKey = DayKey.string(date)
    }
}

enum DayKey {
    static let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Locale(identifier: "zh_CN")
        return cal
    }()

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
}

/// 把 @Query 拿到的分类整理成大类 / 小类的索引
struct CategoryIndex {
    let byID: [UUID: Category]
    let mains: [Category]
    private let childrenByParent: [UUID: [Category]]

    init(_ all: [Category]) {
        byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        mains = all.filter { $0.parentID == nil }.sorted { $0.order < $1.order }
        childrenByParent = Dictionary(grouping: all.filter { $0.parentID != nil }, by: { $0.parentID! })
            .mapValues { $0.sorted { $0.order < $1.order } }
    }

    func children(of id: UUID?) -> [Category] {
        guard let id else { return [] }
        return childrenByParent[id] ?? []
    }

    func name(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return byID[id]?.name
    }

    /// 拼图时用：外套、上衣、下装……按大类顺序排
    func sortKey(_ item: ClothingItem) -> (Int, Int) {
        let main = item.categoryID.flatMap { byID[$0]?.order } ?? Int.max
        let sub = item.subcategoryID.flatMap { byID[$0]?.order } ?? Int.max
        return (main, sub)
    }
}

enum Seeder {
    static let defaultCategories: [(String, [String])] = [
        ("外套", ["夹克", "风衣", "大衣", "羽绒服", "西装", "开衫", "马甲"]),
        ("上衣", ["T恤", "衬衫", "毛衣", "卫衣", "针织衫", "背心/吊带", "Polo衫"]),
        ("连衣裙/套装", ["连衣裙", "套装", "连体裤"]),
        ("下装", ["牛仔裤", "休闲裤", "西裤", "短裤", "半身裙", "运动裤"]),
        ("内衣", ["内裤", "文胸", "秋衣秋裤", "袜子"]),
        ("睡衣/家居服", ["睡衣", "家居服", "睡袍"]),
        ("运动服", ["运动上衣", "运动裤", "泳衣"]),
        ("鞋", ["运动鞋", "皮鞋", "靴子", "凉鞋/拖鞋", "高跟鞋"]),
        ("包", ["双肩包", "斜挎包", "手提包"]),
        ("配饰", ["帽子", "围巾", "腰带", "首饰", "眼镜"]),
    ]

    static let defaultTags = ["春", "夏", "秋", "冬"]

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let key = "didSeedDefaults"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for (i, (name, subs)) in defaultCategories.enumerated() {
            let main = Category(name: name, order: i)
            context.insert(main)
            for (j, sub) in subs.enumerated() {
                context.insert(Category(name: sub, order: j, parentID: main.id))
            }
        }
        for (i, name) in defaultTags.enumerated() {
            context.insert(Tag(name: name, order: i))
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: key)
    }
}
