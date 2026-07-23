import Foundation

extension LauncherStore {
    func showStatus(_ value: String, duration: Duration = .seconds(2)) {
        statusMessageRevision += 1
        let revision = statusMessageRevision
        statusMessage = value
        Task { @MainActor in
            try? await clock.sleep(for: duration)
            guard statusMessageRevision == revision else { return }
            statusMessage = nil
        }
    }
}
