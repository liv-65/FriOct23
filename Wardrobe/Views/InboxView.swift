import SwiftUI
import SwiftData

/// 待分类：抠好的图一张张过，或多选后批量设成同一类
struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(ProcessingQueue.self) private var queue

    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 1 || $0.statusRaw == 2 },
           sort: \ClothingItem.createdAt)
    private var items: [ClothingItem]
    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 0 })
    private var pending: [ClothingItem]

    @State private var batchMode = false
    @State private var skipped: [UUID] = []

    // 分类选择沿用上一张的，连续录同类衣服时更快
    @State private var categoryID: UUID?
    @State private var subcategoryID: UUID?
    @State private var tagIDs: [UUID] = []

    @State private var selection: Set<UUID> = []
    @State private var showingBatchSheet = false

    private var current: ClothingItem? {
        items.first { !skipped.contains($0.id) } ?? items.first
    }

    var body: some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(pending.isEmpty ? "都分好类了" : "正在抠图…", systemImage: pending.isEmpty ? "checkmark.circle" : "wand.and.stars")
                } description: {
                    Text(pending.isEmpty ? "从衣橱右上角 ＋ 导入更多照片" : "还有 \(pending.count) 张在处理，抠好会出现在这里")
                }
            } else if batchMode {
                batchGrid
            } else if let current {
                SingleClassifyView(
                    item: current,
                    remaining: items.count,
                    pendingCount: pending.count,
                    categoryID: $categoryID,
                    subcategoryID: $subcategoryID,
                    tagIDs: $tagIDs,
                    onSave: { save(current) },
                    onSkip: { skip(current) },
                    onDelete: { delete([current]) },
                    onRetry: { queue.retry(current) }
                )
                .id(current.id)
            }
        }
        .navigationTitle("待分类 \(items.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !items.isEmpty {
                Button(batchMode ? "逐张" : "批量") {
                    batchMode.toggle()
                    selection = []
                }
            }
        }
    }

    // MARK: 批量

    private var batchGrid: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                ForEach(items) { item in
                    ItemCell(item: item, selected: selection.contains(item.id))
                        .onTapGesture {
                            if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
                        }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(selection.count == items.count ? "取消全选" : "全选") {
                    selection = selection.count == items.count ? [] : Set(items.map(\.id))
                }
                Spacer()
                Button(role: .destructive) {
                    delete(items.filter { selection.contains($0.id) })
                    selection = []
                } label: { Image(systemName: "trash") }
                    .disabled(selection.isEmpty)
                Button("给 \(selection.count) 件分类") { showingBatchSheet = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)
            }
            .padding()
            .background(.bar)
        }
        .sheet(isPresented: $showingBatchSheet) {
            NavigationStack {
                ScrollView {
                    ClassificationForm(categoryID: $categoryID, subcategoryID: $subcategoryID, tagIDs: $tagIDs)
                        .padding()
                }
                .navigationTitle("批量分类 \(selection.count) 件")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { showingBatchSheet = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            for item in items where selection.contains(item.id) { apply(to: item) }
                            try? context.save()
                            selection = []
                            showingBatchSheet = false
                        }
                        .disabled(categoryID == nil)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: 操作

    private func apply(to item: ClothingItem) {
        item.categoryID = categoryID
        item.subcategoryID = subcategoryID
        item.tagIDs = tagIDs
        item.status = .classified
    }

    private func save(_ item: ClothingItem) {
        apply(to: item)
        try? context.save()
    }

    private func skip(_ item: ClothingItem) {
        skipped.removeAll { $0 == item.id }
        skipped.append(item.id)
        // 都跳过一遍了就从头再来
        if items.allSatisfy({ skipped.contains($0.id) }) { skipped = [] }
    }

    private func delete(_ targets: [ClothingItem]) {
        for item in targets {
            ImageStore.delete(item.allFiles)
            context.delete(item)
        }
        try? context.save()
    }
}

private struct SingleClassifyView: View {
    @Bindable var item: ClothingItem
    let remaining: Int
    let pendingCount: Int
    @Binding var categoryID: UUID?
    @Binding var subcategoryID: UUID?
    @Binding var tagIDs: [UUID]
    let onSave: () -> Void
    let onSkip: () -> Void
    let onDelete: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                FullImage(file: item.displayFile)
                    .frame(height: 300)
                    .frame(maxWidth: .infinity)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                RotateButtons(item: item)

                if !item.hasCutout {
                    HStack {
                        Label("没识别出主体，将使用原图", systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                        Spacer()
                        Button("重试", action: onRetry).font(.footnote)
                    }
                }

                ClassificationForm(categoryID: $categoryID, subcategoryID: $subcategoryID, tagIDs: $tagIDs)

                if pendingCount > 0 {
                    Text("后台还有 \(pendingCount) 张在抠图").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.bordered)
                Button("跳过", action: onSkip)
                    .buttonStyle(.bordered)
                    .disabled(remaining < 2)
                Button(action: onSave) {
                    Text(remaining > 1 ? "保存，下一张" : "保存").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(categoryID == nil)
            }
            .controlSize(.large)
            .padding()
            .background(.bar)
        }
    }
}
