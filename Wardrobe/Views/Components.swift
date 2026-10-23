import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: proposal.width ?? width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct Chip: View {
    let title: String
    var selected = false
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
            .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

struct ThumbImage: View {
    let file: String?

    var body: some View {
        if let image = ImageStore.image(file) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: "tshirt").font(.title2).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// 大图：异步加载，不进缓存
struct FullImage: View {
    let file: String?
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: file) {
            guard let file else { image = nil; return }
            image = await Task.detached { ImageStore.loadUncached(file) }.value
        }
    }
}

struct ItemCell: View {
    let item: ClothingItem
    var caption: String?
    var selected = false
    var height: CGFloat = 110

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if item.status == .pending {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ThumbImage(file: item.displayThumb)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(selected ? Color.accentColor : .clear, lineWidth: 3)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                }
            }
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// 一个带输入框的弹窗，新建和改名都用它
struct NameAlert: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    @Binding var text: String
    let onConfirm: (String) -> Void

    func body(content: Content) -> some View {
        content.alert(title, isPresented: $isPresented) {
            TextField("名称", text: $text)
            Button("确定") {
                let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { onConfirm(name) }
            }
            Button("取消", role: .cancel) {}
        }
    }
}

extension View {
    func nameAlert(_ title: String, isPresented: Binding<Bool>, text: Binding<String>, onConfirm: @escaping (String) -> Void) -> some View {
        modifier(NameAlert(title: title, isPresented: isPresented, text: text, onConfirm: onConfirm))
    }
}
