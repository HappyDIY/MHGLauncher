import SwiftUI

struct CharacterEmptyView: View {
    let isBusy: Bool
    let canSync: Bool
    let refresh: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("暂无角色数据", systemImage: "person.crop.square.stack")
        } description: {
            Text(canSync ? "从米游社同步当前账号的角色资料" : "请先在账号页面选择游戏角色")
        } actions: {
            if canSync {
                Button(action: refresh) {
                    HStack(spacing: 7) {
                        if isBusy { ProgressView().controlSize(.small) }
                        Image(systemName: "arrow.clockwise")
                        Text("从米游社同步")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CharacterListRow: View {
    let character: GameCharacter

    var body: some View {
        HStack(spacing: 11) {
            CharacterIcon(character: character, size: 46)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(character.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(character.elementTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(character.elementColor)
                }
                Text("Lv.\(character.level) · \(character.weaponName.nonempty ?? "未同步武器")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(character.constellation) 命")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}

struct CharacterGridTile: View {
    let character: GameCharacter
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                CharacterIcon(character: character, size: 58)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            Text(character.name)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 5) {
                Label(character.elementTitle, systemImage: character.elementSymbol)
                Spacer(minLength: 2)
                Text("Lv.\(character.level)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text("\(character.constellation) 命 · \(character.weaponName.nonempty ?? "未同步武器")")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 154, alignment: .leading)
        .background(tileBackground, in: .rect(cornerRadius: 8))
        .overlay(borderColor, in: .rect(cornerRadius: 8).stroke(lineWidth: selected ? 1.5 : 0))
    }

    private var tileBackground: Color {
        selected ? character.elementColor.opacity(0.14) : .clear
    }

    private var borderColor: Color {
        selected ? character.elementColor.opacity(0.55) : .clear
    }
}
