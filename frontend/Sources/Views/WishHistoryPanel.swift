import SwiftUI

struct WishHistoryPanel: View {
    let records: [WishRecord]
    let selectedGachaType: String?
    @State private var searchText = ""
    @State private var rankFilter = WishRankFilter.all

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controls
            Table(filteredRecords) {
                TableColumn("时间") { item in
                    Text(item.time.formatted(date: .numeric, time: .shortened))
                        .foregroundStyle(.secondary)
                }
                .width(min: 116, ideal: 142)
                TableColumn("祈愿结果") { item in
                    WishItemCell(item: item)
                }
                TableColumn("星级") { item in
                    Text(String(repeating: "★", count: item.rank))
                        .foregroundStyle(item.rank == 5 ? .orange : item.rank == 4 ? .purple : .secondary)
                }
                .width(72)
                TableColumn("类型", value: \.itemType)
                    .width(54)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private var controls: some View {
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
    }

    private var filteredRecords: [WishRecord] {
        records.filter { item in
            let matchesPool = selectedGachaType == nil
                || item.normalizedGachaType == selectedGachaType
            let matchesRank = rankFilter.rank.map { item.rank == $0 } ?? true
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || item.name.localizedCaseInsensitiveContains(query)
            return matchesPool && matchesRank && matchesSearch
        }
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
