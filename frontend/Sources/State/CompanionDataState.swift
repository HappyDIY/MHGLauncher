import Foundation

extension LauncherStore {
    var activeWishUID: String? { selectedRole?.uid ?? manualWishUID }

    func startCompanionSelection() -> Int {
        companionSelectionIntent &+= 1
        return companionSelectionIntent
    }

    func isCurrentCompanionSelection(_ intent: Int) -> Bool {
        companionSelectionIntent == intent
    }

    func resetCompanionData() -> Int {
        companionDataGeneration &+= 1
        clearWishPresentation()
        wishStatistics = []
        bannerDetails = []
        dailyNote = nil
        characters = []
        selectedCharacterId = nil
        companionLoaded = false
        value.loadedRoleUID = nil
        value.cloudSession = nil
        return companionDataGeneration
    }

    func isCurrentCompanionData(uid: String, generation: Int) -> Bool {
        companionDataGeneration == generation && selectedRole?.uid == uid
    }
}
