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
        let normalizedLockURL = lockURL.standardizedFileURL
        guard normalizedLockURL.path.hasPrefix("/"),
              !normalizedLockURL.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              (try? PrivateFilesystem.ensureDirectory(normalizedLockURL.deletingLastPathComponent())) != nil,
              (try? PrivateFilesystem.rejectSymbolicLinks(in: normalizedLockURL)) != nil else { return nil }
        let descriptor = open(
            normalizedLockURL.path,
            O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { return nil }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1 else {
            close(descriptor)
            return nil
        }
        guard fchmod(descriptor, S_IRUSR | S_IWUSR) == 0 else {
            close(descriptor)
            return nil
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return nil
        }

        guard ftruncate(descriptor, 0) == 0 else {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            return nil
        }
        let pid = "\(ProcessInfo.processInfo.processIdentifier)\n"
        let written = pid.withCString { write(descriptor, $0, strlen($0)) }
        guard written == pid.utf8.count else {
            flock(descriptor, LOCK_UN)
            close(descriptor)
            return nil
        }
        return SingleInstanceGuard(descriptor: descriptor, lockURL: normalizedLockURL)
    }

    static func defaultLockURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let path = environment["MHG_INSTANCE_LOCK_PATH"],
           !path.isEmpty,
           !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) {
            let value = URL(filePath: path).standardizedFileURL
            if value.path.hasPrefix("/") { return value }
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
