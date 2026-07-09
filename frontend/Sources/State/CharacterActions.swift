import Foundation

extension LauncherStore {
    var selectedCharacter: GameCharacter? {
        characters.first { $0.avatarId == selectedCharacterId } ?? characters.first
    }

    func loadCharacters() async {
        guard let uid = selectedRole?.uid else { return }
        await perform {
            let loaded: [GameCharacter] = try await requireClient().get(
                "/v1/characters",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            characters = loaded
            if selectedCharacterId == nil || !loaded.contains(where: { $0.avatarId == selectedCharacterId }) {
                selectedCharacterId = loaded.first?.avatarId
            }
        }
    }

    func refreshCharacters() async {
        await perform {
            characters = try await requireClient().post(
                "/v1/characters/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
            selectedCharacterId = characters.first?.avatarId
        }
    }

    func selectCharacter(_ character: GameCharacter) {
        selectedCharacterId = character.avatarId
    }

    func refreshSelectedCharacterDetail() async {
        guard let character = selectedCharacter else { return }
        await refreshCharacterDetail(character)
    }

    func refreshCharacterDetail(_ character: GameCharacter) async {
        await perform {
            let loaded: GameCharacter = try await requireClient().post(
                "/v1/characters/\(character.avatarId)/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
            if let index = characters.firstIndex(where: { $0.avatarId == loaded.avatarId }) {
                characters[index] = loaded
            } else {
                characters.append(loaded)
            }
            selectedCharacterId = loaded.avatarId
        }
    }
}
