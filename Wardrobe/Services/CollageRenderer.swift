import UIKit

/// 把当天选的几件衣服（透明底）拼成一张图
enum CollageRenderer {
    static func render(_ images: [UIImage], side: CGFloat = 900) -> UIImage {
        let size = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            let n = images.count
            guard n > 0 else { return }
            let cols = n == 1 ? 1 : (n <= 4 ? 2 : 3)
            let rows = Int(ceil(Double(n) / Double(cols)))
            let cellW = side / CGFloat(cols)
            let cellH = side / CGFloat(rows)
            let pad = side * 0.02
            for (i, image) in images.enumerated() {
                let row = i / cols
                let col = i % cols
                // 最后一行不满时居中
                let itemsInRow = row == rows - 1 ? n - row * cols : cols
                let offsetX = CGFloat(cols - itemsInRow) * cellW / 2
                let cell = CGRect(x: offsetX + CGFloat(col) * cellW, y: CGFloat(row) * cellH, width: cellW, height: cellH)
                    .insetBy(dx: pad, dy: pad)
                image.draw(in: aspectFit(image.size, in: cell))
            }
        }
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
