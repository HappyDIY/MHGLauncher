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
        HStack(spacing: 12) {
            CharacterIcon(character: character, size: 52)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(character.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    HStack(spacing: 3) {
                        CharacterElementIcon(character: character, size: 12)
                        Text(character.elementTitle)
                    }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(character.elementColor)
                }
                Text(character.weaponName.nonempty ?? "未同步武器")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(character.level)")
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("等级 · \(character.constellation) 命")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

struct CharacterGridTile: View {
    let character: GameCharacter
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                CharacterIcon(character: character, size: 92)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .tint)
                        .padding(3)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 5) {
                Text(character.name)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 2)
                CharacterElementIcon(character: character, size: 14)
            }
            HStack {
                Text("等级 \(character.level)")
                Spacer()
                Text("\(character.constellation) 命")
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            Text(character.weaponName.nonempty ?? "未同步武器")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 198, alignment: .leading)
        .background(tileBackground, in: .rect(cornerRadius: 8))
        .overlay(borderColor, in: .rect(cornerRadius: 8).stroke(lineWidth: selected ? 2 : 1))
    }

    private var tileBackground: Color {
        character.elementColor.opacity(selected ? 0.14 : 0.055)
    }

    private var borderColor: Color {
        character.elementColor.opacity(selected ? 0.72 : 0.16)
    }
}
