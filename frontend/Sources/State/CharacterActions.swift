import Foundation

extension LauncherStore {
    var selectedCharacter: GameCharacter? {
        characters.first { $0.avatarId == selectedCharacterId } ?? characters.first
    }

    func loadCharacters() async {
        guard let uid = selectedRole?.uid else { return }
        let generation = companionDataGeneration
        await perform {
            let loaded: [GameCharacter] = try await requireClient().get(
                "/v1/characters",
                query: [URLQueryItem(name: "uid", value: uid)]
            )
            guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
            characters = loaded
            if selectedCharacterId == nil || !loaded.contains(where: { $0.avatarId == selectedCharacterId }) {
                selectedCharacterId = loaded.first?.avatarId
            }
        }
    }

    func refreshCharacters() async {
        guard let uid = selectedRole?.uid else { return }
        let generation = companionDataGeneration
        await perform {
            let loaded: [GameCharacter] = try await requireClient().post(
                "/v1/characters/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
            guard isCurrentCompanionData(uid: uid, generation: generation) else { return }
            characters = loaded
            if selectedCharacterId == nil || !loaded.contains(where: { $0.avatarId == selectedCharacterId }) {
                selectedCharacterId = loaded.first?.avatarId
            }
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
        let generation = companionDataGeneration
        let selectedID = selectedCharacterId
        await perform {
            let loaded: GameCharacter = try await requireClient().post(
                "/v1/characters/\(character.avatarId)/refresh",
                body: CredentialRequest(credential: try requireCredential())
            )
            guard isCurrentCompanionData(uid: character.uid, generation: generation) else { return }
            if let index = characters.firstIndex(where: { $0.avatarId == loaded.avatarId }) {
                characters[index] = loaded
            } else {
                characters.append(loaded)
            }
            if selectedCharacterId == selectedID { selectedCharacterId = loaded.avatarId }
        }
    }
}
