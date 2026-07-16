import SwiftUI

struct WishHistoryPanel: View {
    let entries: [WishPityEntry]
    let selectedGachaType: String?
    @State private var searchText = ""
    @State private var rankFilter = WishRankFilter.all
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil

    var body: some View {
        let entries = filteredRecords
        VStack(alignment: .leading, spacing: 12) {
            controls(count: entries.count)
            Table(entries) {
                TableColumn("计数") { entry in
                    Text("\(entry.pity)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(entry.record.rank == 5 ? .orange : .secondary)
                }
                .width(42)
                TableColumn("时间") { entry in
                    Text(WishHistoryPresentation.dateTime(entry.record.time))
                        .foregroundStyle(.secondary)
                }
                .width(min: 116, ideal: 142)
                TableColumn("祈愿结果") { entry in
                    WishItemCell(item: entry.record)
                }
                TableColumn("星级") { entry in
                    Text(String(repeating: "★", count: entry.record.rank))
                        .foregroundStyle(entry.record.rank == 5 ? .orange : entry.record.rank == 4 ? .purple : .secondary)
                }
                .width(72)
                TableColumn("类型", value: \.record.itemType)
                    .width(54)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func controls(count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("祈愿历史")
                        .font(.headline)
                    Text("\(count) 条记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                        .motionAnimation(.content, value: count)
                }
                Spacer()
                Picker("星级", selection: $rankFilter) {
                    ForEach(WishRankFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
                .motionHover(.subtle)
                TextField("搜索名称", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(width: 150, height: 30)
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .motionHover(.subtle)
            }
            dateFilterRow
        }
    }

    private var dateFilterRow: some View {
        HStack(spacing: 8) {
            Toggle(
                "从",
                isOn: dateEnabled(
                    $dateFrom,
                    fallback: calendar.startOfDay(for: entries.last?.record.time ?? Date())
                )
            )
                .toggleStyle(.checkbox)
            DatePicker(
                "从",
                selection: Binding(
                    get: { dateFrom ?? entries.last?.record.time ?? Date() },
                    set: { dateFrom = calendar.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(width: 120)
            .disabled(dateFrom == nil)
            .motionHover(.subtle)

            Toggle("到", isOn: dateEnabled($dateTo, fallback: calendar.endOfDay(for: Date())))
                .toggleStyle(.checkbox)
            DatePicker(
                "到",
                selection: Binding(
                    get: { dateTo ?? Date() },
                    set: { dateTo = calendar.endOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(width: 120)
            .disabled(dateTo == nil)
            .motionHover(.subtle)

            if dateFrom != nil || dateTo != nil {
                Button("清除") {
                    dateFrom = nil
                    dateTo = nil
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .motionHover()
                .motionTransition(.selection)
            }
        }
        .motionAnimation(.selection, value: dateFrom != nil || dateTo != nil)
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = WishHistoryPresentation.timeZone
        return cal
    }

    private func dateEnabled(_ date: Binding<Date?>, fallback: Date) -> Binding<Bool> {
        Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? fallback : nil }
        )
    }

    private var filteredRecords: [WishPityEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            let item = entry.record
            let matchesPool = selectedGachaType == nil
                || item.normalizedGachaType == selectedGachaType
            let matchesRank = rankFilter.rank.map { item.rank == $0 } ?? true
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
            var matchesDate = true
            if let from = dateFrom {
                matchesDate = matchesDate && item.time >= from
            }
            if let to = dateTo {
                matchesDate = matchesDate && item.time <= to
            }
            return matchesPool && matchesRank && matchesSearch && matchesDate
        }
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return self.date(byAdding: components, to: startOfDay(for: date)) ?? date
    }
}

enum WishRankFilter: String, CaseIterable, Identifiable {
    case all
    case five
    case four

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: "全部"
        case .five: "五星"
        case .four: "四星"
        }
    }
    var rank: Int? {
        switch self {
        case .all: nil
        case .five: 5
        case .four: 4
        }
    }
}
