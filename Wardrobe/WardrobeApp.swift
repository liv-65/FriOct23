import SwiftUI
import SwiftData

@main
struct WardrobeApp: App {
    private let container: ModelContainer
    @State private var queue: ProcessingQueue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let container = try! ModelContainer(for: ClothingItem.self, Category.self, Tag.self, OutfitDay.self)
        self.container = container
        _queue = State(initialValue: ProcessingQueue(container: container))
        Seeder.seedIfNeeded(container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(queue)
                .onAppear { queue.start() }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { queue.start() }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            WardrobeView()
                .tabItem { Label("衣橱", systemImage: "hanger") }
            NavigationStack { OutfitPickerView() }
                .tabItem { Label("穿搭", systemImage: "tshirt") }
            CalendarView()
                .tabItem { Label("日历", systemImage: "calendar") }
        }
    }
}
