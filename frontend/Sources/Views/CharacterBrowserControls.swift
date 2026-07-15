import SwiftUI

enum CharacterElementFilter: String, CaseIterable, Identifiable {
    case all
    case fire
    case water
    case wind
    case electric
    case grass
    case ice
    case rock

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部元素"
        case .fire: "火元素"
        case .water: "水元素"
        case .wind: "风元素"
        case .electric: "雷元素"
        case .grass: "草元素"
        case .ice: "冰元素"
        case .rock: "岩元素"
        }
    }

    func matches(_ character: GameCharacter) -> Bool {
        let value = character.element.lowercased()
        return switch self {
        case .all: true
        case .fire: value == "fire" || value == "pyro"
        case .water: value == "water" || value == "hydro"
        case .wind: value == "wind" || value == "anemo"
        case .electric: value == "electric" || value == "electro"
        case .grass: value == "grass" || value == "dendro"
        case .ice: value == "ice" || value == "cryo"
        case .rock: value == "rock" || value == "geo"
        }
    }
}

struct CharacterBrowserControls: View {
    @Binding var searchText: String
    @Binding var layout: CharacterLayout
    @Binding var elementFilter: CharacterElementFilter
    let countText: String
    let roleSummary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField
            HStack(spacing: 8) {
                layoutPicker
                elementMenu
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text("角色")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(countText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Text(roleSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索角色、元素或武器", text: $searchText)
                .textFieldStyle(.plain)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("清除搜索")
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var layoutPicker: some View {
        Picker("布局", selection: $layout) {
            Label("列表", systemImage: "list.bullet").tag(CharacterLayout.list)
            Label("网格", systemImage: "square.grid.2x2").tag(CharacterLayout.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 132)
    }

    private var elementMenu: some View {
        Menu {
            ForEach(CharacterElementFilter.allCases) { filter in
                Button {
                    elementFilter = filter
                } label: {
                    if elementFilter == filter {
                        Label(filter.title, systemImage: "checkmark")
                    } else {
                        Text(filter.title)
                    }
                }
            }
        } label: {
            Text(elementFilter.title)
                .lineLimit(1)
                .frame(minWidth: 82)
        }
        .buttonStyle(.glass)
        .help("按元素筛选")
        .accessibilityLabel("元素筛选：\(elementFilter.title)")
    }
}
