import SwiftUI
import SwiftData

/// 选大类 / 小类 / 标签，没有合适的可以当场新建
struct ClassificationForm: View {
    @Binding var categoryID: UUID?
    @Binding var subcategoryID: UUID?
    @Binding var tagIDs: [UUID]

    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Tag.order) private var tags: [Tag]

    private enum NewKind { case main, sub, tag }
    @State private var newKind: NewKind?
    @State private var showingNew = false
    @State private var newName = ""

    var body: some View {
        let index = CategoryIndex(categories)
        VStack(alignment: .leading, spacing: 14) {
            section("大类") {
                ForEach(index.mains) { main in
                    Chip(title: main.name, selected: categoryID == main.id) {
                        if categoryID != main.id {
                            categoryID = main.id
                            subcategoryID = nil
                        }
                    }
                }
                Chip(title: "新分类", systemImage: "plus") { askNew(.main) }
            }

            if let categoryID, index.byID[categoryID] != nil {
                section("小类") {
                    ForEach(index.children(of: categoryID)) { sub in
                        Chip(title: sub.name, selected: subcategoryID == sub.id) {
                            subcategoryID = subcategoryID == sub.id ? nil : sub.id
                        }
                    }
                    Chip(title: "新小类", systemImage: "plus") { askNew(.sub) }
                }
            }

            section("季节 / 标签（可多选）") {
                ForEach(tags) { tag in
                    Chip(title: tag.name, selected: tagIDs.contains(tag.id)) {
                        if let i = tagIDs.firstIndex(of: tag.id) {
                            tagIDs.remove(at: i)
                        } else {
                            tagIDs.append(tag.id)
                        }
                    }
                }
                Chip(title: "新标签", systemImage: "plus") { askNew(.tag) }
            }
        }
        .nameAlert(alertTitle, isPresented: $showingNew, text: $newName) { name in
            create(name, index: index)
        }
    }

    private var alertTitle: String {
        switch newKind {
        case .main: "新建大类"
        case .sub: "新建小类"
        case .tag: "新建标签"
        case nil: ""
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout { content() }
        }
    }

    private func askNew(_ kind: NewKind) {
        newKind = kind
        newName = ""
        showingNew = true
    }

    private func create(_ name: String, index: CategoryIndex) {
        switch newKind {
        case .main:
            let c = Category(name: name, order: (index.mains.map(\.order).max() ?? -1) + 1)
            context.insert(c)
            categoryID = c.id
            subcategoryID = nil
        case .sub:
            guard let parent = categoryID else { return }
            let c = Category(name: name, order: (index.children(of: parent).map(\.order).max() ?? -1) + 1, parentID: parent)
            context.insert(c)
            subcategoryID = c.id
        case .tag:
            let t = Tag(name: name, order: (tags.map(\.order).max() ?? -1) + 1)
            context.insert(t)
            tagIDs.append(t.id)
        case nil:
            break
        }
        try? context.save()
    }
}
