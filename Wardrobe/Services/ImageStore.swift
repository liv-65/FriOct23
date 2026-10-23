import UIKit

/// 所有图片都存在 App 沙盒 Documents/Images 下，数据库只记文件名
enum ImageStore {
    static let directory: URL = {
        let url = URL.documentsDirectory.appending(path: "Images", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 400
        return c
    }()

    static func url(_ name: String) -> URL { directory.appending(path: name) }

    static func saveJPEG(_ image: UIImage, quality: CGFloat = 0.85) throws -> String {
        guard let data = image.jpegData(compressionQuality: quality) else { throw CocoaError(.fileWriteUnknown) }
        return try write(data, ext: "jpg")
    }

    static func savePNG(_ image: UIImage) throws -> String {
        guard let data = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return try write(data, ext: "png")
    }

    private static func write(_ data: Data, ext: String) throws -> String {
        let name = UUID().uuidString + "." + ext
        try data.write(to: url(name), options: .atomic)
        return name
    }

    /// 缩略图用，带缓存
    static func image(_ name: String?) -> UIImage? {
        guard let name else { return nil }
        if let hit = cache.object(forKey: name as NSString) { return hit }
        guard let img = UIImage(contentsOfFile: url(name).path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }

    /// 大图用，不进缓存
    static func loadUncached(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: url(name).path)
    }

    static func delete(_ names: [String?]) {
        for case let name? in names {
            cache.removeObject(forKey: name as NSString)
            try? FileManager.default.removeItem(at: url(name))
        }
    }
}

extension UIImage {
    /// 等比缩小到最长边不超过 maxSide，同时把方向摆正
    func resized(maxSide: CGFloat) -> UIImage {
        let scale = min(1, maxSide / max(size.width, size.height))
        let newSize = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
