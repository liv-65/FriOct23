import SwiftUI
import SwiftData

struct DayRef: Hashable { let date: Date }

struct CalendarView: View {
    enum Mode: String, CaseIterable { case week = "周", month = "月" }

    @Query private var days: [OutfitDay]
    @State private var mode: Mode = .week
    @State private var anchor = Date.now

    private let cal = DayKey.calendar

    var body: some View {
        let byKey = Dictionary(days.map { ($0.dayKey, $0) }, uniquingKeysWith: { a, _ in a })
        NavigationStack {
            VStack(spacing: 12) {
                Picker("视图", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                    Spacer()
                    Text(title).font(.headline)
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                }
                .padding(.horizontal, 4)

                ScrollView {
                    switch mode {
                    case .week: weekView(byKey)
                    case .month: monthView(byKey)
                    }
                }
                .gesture(DragGesture(minimumDistance: 40).onEnded { value in
                    if abs(value.translation.width) > abs(value.translation.height) {
                        shift(value.translation.width < 0 ? 1 : -1)
                    }
                })
            }
            .padding(.horizontal)
            .navigationTitle("日历")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("今天") { withAnimation { anchor = .now } }
            }
            .navigationDestination(for: DayRef.self) { DayDetailView(date: $0.date) }
        }
    }

    // MARK: 周

    private func weekView(_ byKey: [String: OutfitDay]) -> some View {
        let start = cal.dateInterval(of: .weekOfYear, for: anchor)!.start
        return VStack(spacing: 10) {
            ForEach(0..<7, id: \.self) { offset in
                let date = cal.date(byAdding: .day, value: offset, to: start)!
                let day = byKey[DayKey.string(date)]
                NavigationLink(value: DayRef(date: date)) {
                    HStack(spacing: 14) {
                        VStack(spacing: 2) {
                            Text(Self.weekdayNames[offset]).font(.caption).foregroundStyle(.secondary)
                            Text("\(cal.component(.day, from: date))")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(cal.isDateInToday(date) ? Color.accentColor : .primary)
                        }
                        .frame(width: 44)
                        Group {
                            if let day {
                                ThumbImage(file: day.collageThumb)
                            } else {
                                Text("未记录").font(.footnote).foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        if let day {
                            Text("\(day.itemIDs.count) 件").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 月

    private func monthView(_ byKey: [String: OutfitDay]) -> some View {
        let month = cal.dateInterval(of: .month, for: anchor)!
        let count = cal.range(of: .day, in: .month, for: anchor)!.count
        // 周一为第一列
        let leading = (cal.component(.weekday, from: month.start) - cal.firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Self.weekdayNames, id: \.self) {
                    Text($0).font(.caption).foregroundStyle(.secondary)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 72) }
                ForEach(0..<count, id: \.self) { i in
                    let date = cal.date(byAdding: .day, value: i, to: month.start)!
                    let day = byKey[DayKey.string(date)]
                    NavigationLink(value: DayRef(date: date)) {
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
                            if let day {
                                ThumbImage(file: day.collageThumb).padding(EdgeInsets(top: 14, leading: 2, bottom: 2, trailing: 2))
                            }
                            Text("\(i + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(cal.isDateInToday(date) ? Color.white : .secondary)
                                .padding(.horizontal, 4).padding(.vertical, 1)
                                .background(cal.isDateInToday(date) ? Color.accentColor : .clear, in: Capsule())
                                .padding(3)
                        }
                        .frame(height: 72)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    static let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var title: String {
        switch mode {
        case .month:
            let c = cal.dateComponents([.year, .month], from: anchor)
            return "\(c.year!)年\(c.month!)月"
        case .week:
            let interval = cal.dateInterval(of: .weekOfYear, for: anchor)!
            let end = cal.date(byAdding: .day, value: 6, to: interval.start)!
            let s = cal.dateComponents([.month, .day], from: interval.start)
            let e = cal.dateComponents([.month, .day], from: end)
            return "\(s.month!)月\(s.day!)日 – \(e.month!)月\(e.day!)日"
        }
    }

    private func shift(_ delta: Int) {
        withAnimation {
            anchor = cal.date(byAdding: mode == .week ? .weekOfYear : .month, value: delta, to: anchor)!
        }
    }
}

struct DayDetailView: View {
    let date: Date
    @Query private var days: [OutfitDay]
    @Query(filter: #Predicate<ClothingItem> { $0.statusRaw == 3 }) private var items: [ClothingItem]
    @Query(sort: \Category.order) private var categories: [Category]

    init(date: Date) {
        self.date = date
        let key = DayKey.string(date)
        _days = Query(filter: #Predicate<OutfitDay> { $0.dayKey == key })
    }

    var body: some View {
        let index = CategoryIndex(categories)
        ScrollView {
            VStack(spacing: 16) {
                if let day = days.first {
                    FullImage(file: day.collageFile)
                        .frame(height: 340)
                        .frame(maxWidth: .infinity)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                    let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                    LazyVGrid(columns: WardrobeView.columns, spacing: 10) {
                        ForEach(day.itemIDs.compactMap { byID[$0] }) { item in
                            NavigationLink { ItemEditView(item: item) } label: {
                                ItemCell(item: item, caption: index.name(item.subcategoryID) ?? index.name(item.categoryID))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else {
                    ContentUnavailableView("这天还没有记录", systemImage: "calendar.badge.plus")
                }
                NavigationLink {
                    OutfitPickerView(date: date)
                } label: {
                    Text(days.isEmpty ? "记录这天的穿搭" : "修改穿搭").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .navigationTitle(date.formatted(.dateTime.locale(Locale(identifier: "zh_CN")).month().day().weekday()))
        .navigationBarTitleDisplayMode(.inline)
    }
}
