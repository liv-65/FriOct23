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
            await processAll()
            isProcessing = false
        }
    }

    /// 重新抠图（比如之前失败的）
    func retry(_ item: ClothingItem) {
        ImageStore.delete([item.cutoutFile, item.cutoutThumb])
        item.cutoutFile = nil
        item.cutoutThumb = nil
        item.status = .pending
        try? container.mainContext.save()
        start()
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
            let result = await Task.detached(priority: .utility) {
                autoreleasepool { Self.process(file) }
            }.value

            // 处理期间被删了就丢掉结果
            guard !item.isDeleted, item.modelContext != nil else {
                ImageStore.delete([result.originalThumb, result.cutout, result.cutoutThumb])
                continue
            }
            if item.originalThumb == nil {
                item.originalThumb = result.originalThumb
            } else {
                ImageStore.delete([result.originalThumb])
            }
            item.cutoutFile = result.cutout
            item.cutoutThumb = result.cutoutThumb
            item.useCutout = result.cutout != nil
            item.status = result.cutout == nil ? .failed : .unclassified
            try? context.save()
        }
    }

    private struct Result: Sendable {
        var originalThumb: String?
        var cutout: String?
        var cutoutThumb: String?
    }

    nonisolated private static func process(_ file: String) -> Result {
        var result = Result()
        guard let image = ImageStore.loadUncached(file) else { return result }
        result.originalThumb = try? ImageStore.saveJPEG(image.resized(maxSide: 400), quality: 0.8)
        if let cut = try? BackgroundRemover.cutout(image) {
            result.cutout = try? ImageStore.savePNG(cut.resized(maxSide: 1200))
            result.cutoutThumb = try? ImageStore.savePNG(cut.resized(maxSide: 400))
        }
        return result
    }
}
