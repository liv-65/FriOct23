import SwiftUI
import SwiftData
import PhotosUI

/// 导入相册照片 + 后台逐张抠图。进度都在数据库里（status = pending），App 重开后会接着处理
@MainActor
@Observable
final class ProcessingQueue {
    private(set) var isProcessing = false
    private(set) var importTotal = 0
    private(set) var importDone = 0
    private(set) var rotating: Set<UUID> = []

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    var isImporting: Bool { importTotal > 0 }

    func importPhotos(_ selections: [PhotosPickerItem]) async {
        guard !selections.isEmpty else { return }
        importTotal += selections.count
        let context = container.mainContext
        for selection in selections {
            if let data = try? await selection.loadTransferable(type: Data.self) {
                let name = await Task.detached(priority: .userInitiated) { () -> String? in
                    autoreleasepool {
                        guard let image = UIImage(data: data) else { return nil }
                        return try? ImageStore.saveJPEG(image.resized(maxSide: 2048), quality: 0.9)
                    }
                }.value
                if let name {
                    context.insert(ClothingItem(originalFile: name))
                    try? context.save()
                    start()
                }
            }
            importDone += 1
        }
        if importDone >= importTotal {
            importTotal = 0
            importDone = 0
        }
    }

    func start() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            dropLeftoverOriginals()
            await processAll()
            isProcessing = false
        }
    }

    /// 重新抠图（之前失败的，原图还在）
    func retry(_ item: ClothingItem) {
        guard item.hasOriginal else { return }
        item.status = .pending
        try? container.mainContext.save()
        start()
    }

    /// 顺时针或逆时针转 90°，直接改写存储的图片
    func rotate(_ item: ClothingItem, clockwise: Bool) async {
        guard !rotating.contains(item.id), let file = item.displayFile else { return }
        rotating.insert(item.id)
        defer { rotating.remove(item.id) }

        let isCutout = item.hasCutout
        let result = await Task.detached(priority: .userInitiated) { () -> (String, String?)? in
            autoreleasepool {
                guard let image = ImageStore.loadUncached(file) else { return nil }
                let rotated = image.rotated90(clockwise: clockwise)
                let thumb = rotated.resized(maxSide: 400)
                if isCutout {
                    guard let full = try? ImageStore.savePNG(rotated) else { return nil }
                    return (full, try? ImageStore.savePNG(thumb))
                } else {
                    guard let full = try? ImageStore.saveJPEG(rotated, quality: 0.9) else { return nil }
                    return (full, try? ImageStore.saveJPEG(thumb, quality: 0.8))
                }
            }
        }.value

        guard let result, !item.isDeleted, item.modelContext != nil else { return }
        if isCutout {
            ImageStore.delete([item.cutoutFile, item.cutoutThumb])
            item.cutoutFile = result.0
            item.cutoutThumb = result.1
        } else {
            ImageStore.delete([item.originalFile, item.originalThumb])
            item.originalFile = result.0
            item.originalThumb = result.1
        }
        try? container.mainContext.save()
    }

    /// 旧版本抠图成功后还留着原图，这里清掉
    private func dropLeftoverOriginals() {
        let context = container.mainContext
        let descriptor = FetchDescriptor<ClothingItem>(
            predicate: #Predicate { $0.cutoutFile != nil && ($0.originalFile != "" || $0.originalThumb != nil) }
        )
        guard let items = try? context.fetch(descriptor), !items.isEmpty else { return }
        for item in items { item.dropOriginal() }
        try? context.save()
    }

    private func processAll() async {
        let context = container.mainContext
        let pending = ItemStatus.pending.rawValue
        while true {
            var descriptor = FetchDescriptor<ClothingItem>(
                predicate: #Predicate { $0.statusRaw == pending },
                sortBy: [SortDescriptor(\.createdAt)]
            )
            descriptor.fetchLimit = 1
            guard let item = try? context.fetch(descriptor).first else { break }

            let file = item.originalFile
            let needsThumb = item.originalThumb == nil
            let result = await Task.detached(priority: .utility) {
                autoreleasepool { Self.process(file, needsThumb: needsThumb) }
            }.value

            // 处理期间被删了就丢掉结果
            guard !item.isDeleted, item.modelContext != nil else {
                ImageStore.delete([result.originalThumb, result.cutout, result.cutoutThumb])
                continue
            }
            if let cutout = result.cutout {
                item.cutoutFile = cutout
                item.cutoutThumb = result.cutoutThumb
                item.dropOriginal()
                item.status = .unclassified
            } else {
                if let thumb = result.originalThumb { item.originalThumb = thumb }
                item.status = .failed
            }
            try? context.save()
        }
    }

    private struct Result: Sendable {
        var originalThumb: String?
        var cutout: String?
        var cutoutThumb: String?
    }

    nonisolated private static func process(_ file: String, needsThumb: Bool) -> Result {
        var result = Result()
        guard !file.isEmpty, let image = ImageStore.loadUncached(file) else { return result }
        if let cut = try? BackgroundRemover.cutout(image) {
            result.cutout = try? ImageStore.savePNG(cut.resized(maxSide: 1200))
            result.cutoutThumb = try? ImageStore.savePNG(cut.resized(maxSide: 400))
        }
        // 抠图失败时才需要原图缩略图
        if result.cutout == nil && needsThumb {
            result.originalThumb = try? ImageStore.saveJPEG(image.resized(maxSide: 400), quality: 0.8)
        }
        return result
    }
}
