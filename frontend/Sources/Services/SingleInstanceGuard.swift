import AppKit
import Darwin
import Foundation

final class SingleInstanceGuard {
    private let descriptor: Int32
    let lockURL: URL

    private init(descriptor: Int32, lockURL: URL) {
        self.descriptor = descriptor
        self.lockURL = lockURL
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    static func acquire(lockURL: URL = defaultLockURL()) -> SingleInstanceGuard? {
        try? FileManager.default.createDirectory(
            at: lockURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let descriptor = open(lockURL.path, O_RDWR | O_CREAT, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        ftruncate(descriptor, 0)
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        _ = pid.withCString { write(descriptor, $0, strlen($0)) }
        return SingleInstanceGuard(descriptor: descriptor, lockURL: lockURL)
    }

    static func defaultLockURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let path = environment["MHG_INSTANCE_LOCK_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/MHGLauncher/app.lock")
    }

    static func activateExistingApplication(
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) {
        guard let bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let applications = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        )
        applications
            .first { $0.processIdentifier != currentPID }?
            .activate(options: [.activateAllWindows])
    }
}
