import SwiftUI

struct WishHistoryPanel: View {
    let records: [WishRecord]
    let selectedGachaType: String?
    @State private var searchText = ""
    @State private var rankFilter = WishRankFilter.all
    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            Table(filteredRecords) {
                TableColumn("计数") { entry in
                    Text("\(entry.pity)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(entry.record.rank == 5 ? .orange : .secondary)
                }
                .width(42)
                TableColumn("时间") { entry in
                    Text(entry.record.time.formatted(date: .numeric, time: .shortened))
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

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("祈愿历史")
                        .font(.headline)
                    Text("\(filteredRecords.count) 条记录")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
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
                TextField("搜索名称", text: $searchText)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 11)
                    .frame(width: 150, height: 30)
                    .glassEffect(.clear.interactive(), in: .capsule)
            }
            dateFilterRow
        }
    }

    private var dateFilterRow: some View {
        HStack(spacing: 8) {
            DatePicker(
                "从",
                selection: Binding(
                    get: { dateFrom ?? records.first?.time ?? Date() },
                    set: { dateFrom = calendar.startOfDay(for: $0) }
                ),
                displayedComponents: .date
            )
            .labelsHidden()
            .datePickerStyle(.compact)
            .frame(width: 120)

            Text("至")
                .font(.caption)
                .foregroundStyle(.secondary)

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

            if dateFrom != nil || dateTo != nil {
                Button("清除") {
                    dateFrom = nil
                    dateTo = nil
                }
                .buttonStyle(.glass)
                .controlSize(.small)
            }
        }
    }

    private var calendar: Calendar {
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }

    private struct PityEntry: Identifiable {
        var id: String { record.id }
        let record: WishRecord
        let pity: Int
    }

    private var filteredRecords: [PityEntry] {
        let matches = records.filter { item in
            let matchesPool = selectedGachaType == nil
                || item.normalizedGachaType == selectedGachaType
            let matchesRank = rankFilter.rank.map { item.rank == $0 } ?? true
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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
        return buildPityEntries(matches)
    }

    private func buildPityEntries(_ list: [WishRecord]) -> [PityEntry] {
        var pityMap: [String: Int] = [:]
        var counter = 0
        for record in list.reversed() {
            counter += 1
            pityMap[record.id] = counter
            if record.rank == 5 {
                counter = 0
            }
        }
        return list.map { entry in
            PityEntry(record: entry, pity: pityMap[entry.id] ?? 1)
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
