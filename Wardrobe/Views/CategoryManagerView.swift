import SwiftUI
import SwiftData

/// 管理大类、小类和标签：新增、改名、删除、拖动排序
struct CategoryManagerView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Tag.order) private var tags: [Tag]

    @State private var editor = NameEditor()

    var body: some View {
        let index = CategoryIndex(categories)
        List {
            Section {
                ForEach(index.mains) { main in
                    NavigationLink {
                        SubcategoryManagerView(parent: main)
                    } label: {
                        HStack {
                            Text(main.name)
                            Spacer()
                            Text("\(index.children(of: main.id).count) 个小类").foregroundStyle(.secondary).font(.footnote)
                        }
                    }
                    .swipeActions {
                        Button("删除", role: .destructive) {
                            for child in index.children(of: main.id) { context.delete(child) }
                            context.delete(main)
                            try? context.save()
                        }
                        Button("改名") { editor.rename(main.name) { main.name = $0 } }.tint(.blue)
                    }
                }
                .onMove { reorder(index.mains, from: $0, to: $1) }
                Button { editor.create("新建大类") { name in
                    context.insert(Category(name: name, order: (index.mains.map(\.order).max() ?? -1) + 1))
                } } label: { Label("新增大类", systemImage: "plus") }
            } header: {
                Text("分类")
            } footer: {
                Text("左滑可改名或删除。删除分类不会删除衣服，衣服会出现在衣橱的「未分类」里。")
            }

            Section("季节 / 标签") {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .swipeActions {
                            Button("删除", role: .destructive) { context.delete(tag); try? context.save() }
                            Button("改名") { editor.rename(tag.name) { tag.name = $0 } }.tint(.blue)
                        }
                }
                .onMove { source, dest in
                    var arr = tags
                    arr.move(fromOffsets: source, toOffset: dest)
                    for (i, t) in arr.enumerated() { t.order = i }
                    try? context.save()
                }
                Button { editor.create("新建标签") { name in
                    context.insert(Tag(name: name, order: (tags.map(\.order).max() ?? -1) + 1))
                } } label: { Label("新增标签", systemImage: "plus") }
            }
        }
        .navigationTitle("分类管理")
        .toolbar { EditButton() }
        .nameAlert(editor.title, isPresented: $editor.isPresented, text: $editor.text) { name in
            editor.onConfirm?(name)
            try? context.save()
        }
    }

    private func reorder(_ list: [Category], from source: IndexSet, to dest: Int) {
        var arr = list
        arr.move(fromOffsets: source, toOffset: dest)
        for (i, c) in arr.enumerated() { c.order = i }
        try? context.save()
    }
}

struct SubcategoryManagerView: View {
    let parent: Category
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    @State private var editor = NameEditor()

    var body: some View {
        let children = CategoryIndex(categories).children(of: parent.id)
        List {
            ForEach(children) { child in
                Text(child.name)
                    .swipeActions {
                        Button("删除", role: .destructive) { context.delete(child); try? context.save() }
                        Button("改名") { editor.rename(child.name) { child.name = $0 } }.tint(.blue)
                    }
            }
            .onMove { source, dest in
                var arr = children
                arr.move(fromOffsets: source, toOffset: dest)
                for (i, c) in arr.enumerated() { c.order = i }
                try? context.save()
            }
            Button { editor.create("新建小类") { name in
                context.insert(Category(name: name, order: (children.map(\.order).max() ?? -1) + 1, parentID: parent.id))
            } } label: { Label("新增小类", systemImage: "plus") }
        }
        .navigationTitle(parent.name)
        .toolbar {
            EditButton()
            Button("改名") { editor.rename(parent.name) { parent.name = $0 } }
        }
        .nameAlert(editor.title, isPresented: $editor.isPresented, text: $editor.text) { name in
            editor.onConfirm?(name)
            try? context.save()
        }
    }
}

struct NameEditor {
    var isPresented = false
    var title = ""
    var text = ""
    var onConfirm: ((String) -> Void)?

    mutating func create(_ title: String, _ action: @escaping (String) -> Void) {
        self.title = title
        text = ""
        onConfirm = action
        isPresented = true
    }

    mutating func rename(_ current: String, _ action: @escaping (String) -> Void) {
        title = "改名"
        text = current
        onConfirm = action
        isPresented = true
    }
}
