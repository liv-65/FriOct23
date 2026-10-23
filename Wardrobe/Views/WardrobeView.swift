import SwiftUI
import SwiftData
import PhotosUI

struct WardrobeView: View {
    @Environment(ProcessingQueue.self) private var queue

    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 3 }, sort: \ClothingItem.createdAt, order: .reverse)
    private var items: [ClothingItem]
    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 1 || $0.statusRaw == 2 })
    private var inbox: [ClothingItem]
    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 0 })
    private var pending: [ClothingItem]
    @Query(sort: \Category.order) private var categories: [Category]

    @State private var filter = ItemFilter()
    @State private var pickerItems: [PhotosPickerItem] = []

    var body: some View {
        let index = CategoryIndex(categories)
        let visible = items.filter { filter.matches($0) }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusBanners
                    ItemFilterBar(filter: $filter)

                    if items.isEmpty {
                        ContentUnavailableView {
                            Label("衣橱还是空的", systemImage: "hanger")
                        } description: {
                            Text("点右上角 ＋ 从相册选一批衣服照片，会自动抠图，然后到「待分类」里归类")
                        }
                        .padding(.top, 40)
                    } else if visible.isEmpty {
                        Text("没有符合筛选的衣服").foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top, 40)
                    } else {
                        ForEach(groups(visible, index: index), id: \.title) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text("\(group.title)  \(group.items.count)").font(.headline)
                                LazyVGrid(columns: Self.columns, spacing: 10) {
                                    ForEach(group.items) { item in
                                        NavigationLink(value: item) {
                                            ItemCell(item: item, caption: index.name(item.subcategoryID))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("衣橱")
            .navigationDestination(for: ClothingItem.self) { ItemEditView(item: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { CategoryManagerView() } label: { Image(systemName: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    PhotosPicker(selection: $pickerItems, matching: .images, photoLibrary: .shared()) {
                        Image(systemName: "plus")
                    }
                }
            }
            .onChange(of: pickerItems) { _, newValue in
                guard !newValue.isEmpty else { return }
                pickerItems = []
                Task { await queue.importPhotos(newValue) }
            }
        }
    }

    static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    @ViewBuilder
    private var statusBanners: some View {
        if queue.isImporting {
            banner(icon: "square.and.arrow.down", text: "正在导入 \(queue.importDone)/\(queue.importTotal)", showProgress: true)
        }
        if !pending.isEmpty {
            banner(icon: "wand.and.stars", text: "正在抠图，剩余 \(pending.count) 张", showProgress: true)
        }
        if !inbox.isEmpty {
            NavigationLink { InboxView() } label: {
                HStack {
                    Image(systemName: "tray.full.fill")
                    Text("\(inbox.count) 件待分类").fontWeight(.semibold)
                    Spacer()
                    Text("去分类")
                    Image(systemName: "chevron.right")
                }
                .padding()
                .foregroundStyle(.white)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private func banner(icon: String, text: String, showProgress: Bool) -> some View {
        HStack {
            Image(systemName: icon)
            Text(text)
            Spacer()
            if showProgress { ProgressView() }
        }
        .padding()
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    private struct ItemGroup { let title: String; let items: [ClothingItem] }

    private func groups(_ items: [ClothingItem], index: CategoryIndex) -> [ItemGroup] {
        var result: [ItemGroup] = []
        for main in index.mains {
            let matched = items.filter { $0.categoryID == main.id }
                .sorted { index.sortKey($0) < index.sortKey($1) }
            if !matched.isEmpty { result.append(ItemGroup(title: main.name, items: matched)) }
        }
        let orphans = items.filter { item in
            guard let id = item.categoryID, let c = index.byID[id] else { return true }
            return c.parentID != nil
        }
        if !orphans.isEmpty { result.append(ItemGroup(title: "未分类", items: orphans)) }
        return result
    }
}

struct ItemFilter {
    var categoryID: UUID?
    var tagID: UUID?

    func matches(_ item: ClothingItem) -> Bool {
        if let categoryID, item.categoryID != categoryID { return false }
        if let tagID, !item.tagIDs.contains(tagID) { return false }
        return true
    }
}

struct ItemFilterBar: View {
    @Binding var filter: ItemFilter
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Tag.order) private var tags: [Tag]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Chip(title: "全部季节", selected: filter.tagID == nil) { filter.tagID = nil }
                    ForEach(tags) { tag in
                        Chip(title: tag.name, selected: filter.tagID == tag.id) {
                            filter.tagID = filter.tagID == tag.id ? nil : tag.id
                        }
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Chip(title: "全部分类", selected: filter.categoryID == nil) { filter.categoryID = nil }
                    ForEach(CategoryIndex(categories).mains) { main in
                        Chip(title: main.name, selected: filter.categoryID == main.id) {
                            filter.categoryID = filter.categoryID == main.id ? nil : main.id
                        }
                    }
                }
            }
        }
    }
}

struct ItemEditView: View {
    @Bindable var item: ClothingItem
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(ProcessingQueue.self) private var queue
    @State private var confirmDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FullImage(file: item.displayFile)
                    .frame(height: 320)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                if item.hasCutout {
                    Picker("显示", selection: $item.useCutout) {
                        Text("抠图").tag(true)
                        Text("原图").tag(false)
                    }
                    .pickerStyle(.segmented)
                } else {
                    Button("重新抠图") { queue.retry(item) }
                }

                ClassificationForm(categoryID: $item.categoryID, subcategoryID: $item.subcategoryID, tagIDs: $item.tagIDs)

                VStack(alignment: .leading, spacing: 8) {
                    Text("备注").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    TextField("品牌、尺码、购买时间…", text: $item.note, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                }

                Button("删除这件衣服", role: .destructive) { confirmDelete = true }
                    .frame(maxWidth: .infinity)
                    .padding(.top)
            }
            .padding()
        }
        .navigationTitle("编辑")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
        .confirmationDialog("删除后无法恢复", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                ImageStore.delete(item.allFiles)
                context.delete(item)
                try? context.save()
                dismiss()
            }
        }
    }
}
