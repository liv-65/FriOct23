import SwiftUI
import SwiftData

/// 选某一天穿了哪些衣服，保存时拼成一张图放进日历
struct OutfitPickerView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 3 }, sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]
    @Query(sort: \Category.order) private var categories: [Category]

    @State private var date: Date
    @State private var selected: [UUID] = []
    @State private var filter = ItemFilter()
    @State private var saving = false
    @State private var savedMessage: String?

    init(date: Date = .now) {
        _date = State(initialValue: date)
    }

    var body: some View {
        let index = CategoryIndex(categories)
        let visible = items.filter { filter.matches($0) }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DatePicker("日期", selection: $date, in: ...Date.now.addingTimeInterval(86400 * 30), displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                ItemFilterBar(filter: $filter)
                if items.isEmpty {
                    ContentUnavailableView("衣橱里还没有衣服", systemImage: "hanger", description: Text("先去「衣橱」导入并分类"))
                } else {
                    LazyVGrid(columns: WardrobeView.columns, spacing: 10) {
                        ForEach(visible) { item in
                            ItemCell(item: item, caption: index.name(item.subcategoryID) ?? index.name(item.categoryID),
                                     selected: selected.contains(item.id))
                                .onTapGesture { toggle(item.id) }
                        }
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("穿搭")
        .task(id: DayKey.string(date)) { loadExisting() }
        .overlay(alignment: .top) {
            if let savedMessage {
                Text(savedMessage)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: savedMessage)
    }

    private var bottomBar: some View {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return HStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if selected.isEmpty {
                        Text("点衣服选择今天穿的").font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(selected, id: \.self) { id in
                        if let item = byID[id] {
                            ThumbImage(file: item.displayThumb)
                                .frame(width: 40, height: 40)
                                .onTapGesture { toggle(id) }
                        }
                    }
                }
            }
            Button {
                Task { await save(byID: byID) }
            } label: {
                if saving { ProgressView() } else { Text(selected.isEmpty ? "清空这天" : "保存 \(selected.count) 件") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(saving)
        }
        .padding()
        .background(.bar)
    }

    private func toggle(_ id: UUID) {
        if let i = selected.firstIndex(of: id) { selected.remove(at: i) } else { selected.append(id) }
    }

    private func existingDay() -> OutfitDay? {
        let key = DayKey.string(date)
        let descriptor = FetchDescriptor<OutfitDay>(predicate: #Predicate { $0.dayKey == key })
        return try? context.fetch(descriptor).first
    }

    private func loadExisting() {
        selected = existingDay()?.itemIDs ?? []
    }

    private func save(byID: [UUID: ClothingItem]) async {
        saving = true
        defer { saving = false }
        let existing = existingDay()

        if selected.isEmpty {
            if let existing {
                ImageStore.delete([existing.collageFile, existing.collageThumb])
                context.delete(existing)
                try? context.save()
            }
            flash("已清空")
            return
        }

        let index = CategoryIndex(categories)
        let files = selected.compactMap { byID[$0] }
            .sorted { index.sortKey($0) < index.sortKey($1) }
            .map(\.displayFile)
        let rendered = await Task.detached(priority: .userInitiated) { () -> (String?, String?) in
            autoreleasepool {
                let images = files.compactMap { ImageStore.loadUncached($0)?.resized(maxSide: 600) }
                let collage = CollageRenderer.render(images)
                return (try? ImageStore.savePNG(collage), try? ImageStore.savePNG(collage.resized(maxSide: 300)))
            }
        }.value

        let day = existing ?? {
            let d = OutfitDay(date: date)
            context.insert(d)
            return d
        }()
        ImageStore.delete([day.collageFile, day.collageThumb])
        day.itemIDs = selected
        day.collageFile = rendered.0
        day.collageThumb = rendered.1
        try? context.save()
        flash("已保存到日历")
    }

    private func flash(_ text: String) {
        savedMessage = text
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            savedMessage = nil
        }
    }
}
