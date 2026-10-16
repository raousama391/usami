import Foundation

/// Stores sign-in tokens in a private file instead of the Keychain.
///
/// Usami is ad-hoc signed, so every new build has a different code hash. The Keychain pins each
/// item to the hash of the build that created it and asks for the login password whenever a newer
/// build reads it, which meant a password prompt after every update. A file in the user's own
/// Application Support folder (owner-only permissions) doesn't depend on who signed the app, so
/// updates are silent.
enum TokenStore {
    private static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Usami", isDirectory: true)
    }

    private static func url(_ account: String) -> URL {
        directory.appendingPathComponent("\(account).token")
    }

    static func set(_ data: Data, for account: String) {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            let target = url(account)
            try data.write(to: target, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
        } catch {
            DebugLog.write("token store: couldn't save \(account): \(error.localizedDescription)")
        }
    }

    static func get(_ account: String) -> Data? {
        try? Data(contentsOf: url(account))
    }

    static func delete(_ account: String) {
        try? FileManager.default.removeItem(at: url(account))
    }
}
