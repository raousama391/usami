import AppKit
import CryptoKit
import Foundation

/// Checks GitHub Releases for a newer Usami and, if allowed, downloads, verifies and installs it.
/// The only network endpoints touched are api.github.com and this repository's release assets.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private static let repo = "raousama391/usami"
    private static let checkInterval: TimeInterval = 6 * 60 * 60

    struct Release: Equatable {
        let version: String
        let pageURL: URL
        let dmgURL: URL
        let checksumURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var release: Release?

    /// Set by the app so an automatic install never interrupts an open suggestion card.
    var isBusy: () -> Bool = { false }

    private var timer: Timer?
    private var lastCheck = Date.distantPast
    private var working = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Self-install only works for a normal install location the user can write to.
    var canSelfInstall: Bool {
        let path = Bundle.main.bundleURL.path
        let home = NSHomeDirectory()
        let inApplications = path.hasPrefix("/Applications/") || path.hasPrefix("\(home)/Applications/")
        return inApplications && FileManager.default.isWritableFile(atPath: Bundle.main.bundleURL.deletingLastPathComponent().path)
    }

    // MARK: Scheduling

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // First check shortly after launch.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.tick() }
    }

    private func tick() {
        guard !working, Settings.shared.updateMode != .off else { return }
        if Date().timeIntervalSince(lastCheck) >= Self.checkInterval {
            Task { await check(userInitiated: false) }
            return
        }
        if Settings.shared.updateMode == .automatic, canSelfInstall, release != nil,
           case .available = state, !isBusy() {
            Task { await install() }
        }
    }

    // MARK: Check

    func check(userInitiated: Bool) async {
        guard !working else { return }
        working = true
        defer { working = false }
        state = .checking
        lastCheck = Date()

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Usami/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
                  let assets = json["assets"] as? [[String: Any]] else {
                throw ProviderError.other("Couldn't read the latest release.")
            }
            let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

            func asset(_ name: String) -> URL? {
                guard let urlString = assets.first(where: { $0["name"] as? String == name })?["browser_download_url"] as? String,
                      let url = URL(string: urlString), Self.isTrustedAsset(url) else { return nil }
                return url
            }

            guard Self.isNewer(version, than: currentVersion) else {
                release = nil
                state = .upToDate
                return
            }
            guard let dmg = asset("Usami.dmg") else {
                throw ProviderError.other("Release \(tag) has no downloadable build yet.")
            }
            release = Release(version: version, pageURL: page, dmgURL: dmg, checksumURL: asset("Usami.dmg.sha256"))
            state = .available(version)
            DebugLog.write("update available: \(version) (current \(currentVersion))")
        } catch {
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    // MARK: Install

    func install() async {
        guard !working, let release else { return }
        guard canSelfInstall else {
            NSWorkspace.shared.open(release.pageURL)
            return
        }
        working = true
        defer { working = false }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("usami-update-\(UUID().uuidString)")
        do {
            state = .downloading
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

            // 1. Download the DMG.
            let (tmp, response) = try await URLSession.shared.download(from: release.dmgURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw ProviderError.other("Download failed.")
            }
            let dmg = work.appendingPathComponent("Usami.dmg")
            try FileManager.default.moveItem(at: tmp, to: dmg)

            // 2. Verify the published SHA-256 when there is one.
            if let checksumURL = release.checksumURL {
                let (data, _) = try await URLSession.shared.data(from: checksumURL)
                let expected = String(decoding: data, as: UTF8.self)
                    .split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
                let actual = SHA256.hash(data: try Data(contentsOf: dmg)).map { String(format: "%02x", $0) }.joined()
                guard !expected.isEmpty, expected.lowercased() == actual else {
                    throw ProviderError.other("The download didn't match its checksum, so it was discarded.")
                }
            }

            // 3. Mount, stage the app, unmount.
            let mount = work.appendingPathComponent("mnt")
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try await Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path])

            let stagedApp = work.appendingPathComponent("Usami.app")
            do {
                try FileManager.default.copyItem(at: mount.appendingPathComponent("Usami.app"), to: stagedApp)
            } catch {
                _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
                throw error
            }
            // Unmount right away (synchronously) so no volume is left behind when we quit.
            _ = try? await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])

            // 4. Sanity-check what we're about to install.
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", stagedApp.path])
            let plist = NSDictionary(contentsOf: stagedApp.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
                  plist?["CFBundleShortVersionString"] as? String == release.version else {
                throw ProviderError.other("The downloaded app didn't match the expected release.")
            }

            // 5. Hand over to a helper that swaps the app after we quit, then relaunches it.
            state = .installing
            let script = work.appendingPathComponent("swap.sh")
            try Self.swapScript.write(to: script, atomically: true, encoding: .utf8)
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/bash")
            helper.arguments = [
                script.path,
                String(ProcessInfo.processInfo.processIdentifier),
                stagedApp.path,
                Bundle.main.bundleURL.path,
                work.path,
            ]
            helper.standardInput = FileHandle.nullDevice
            helper.standardOutput = FileHandle.nullDevice
            helper.standardError = FileHandle.nullDevice
            try helper.run()
            DebugLog.write("installing update \(release.version); relaunching")
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        } catch {
            try? FileManager.default.removeItem(at: work)
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: Helpers

    private static let swapScript = """
    #!/bin/bash
    # usage: swap.sh <old-pid> <new-app> <dest-app> <workdir>
    PID="$1"; NEW="$2"; DEST="$3"; WORK="$4"
    for _ in $(seq 1 100); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
    rm -rf "$DEST" && cp -R "$NEW" "$DEST" && xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
    open "$DEST"
    hdiutil detach "$WORK/mnt" -quiet -force 2>/dev/null
    rm -rf "$WORK"
    """

    @discardableResult
    private static func run(_ executable: String, _ arguments: [String]) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                let out = Pipe()
                process.standardOutput = out
                process.standardError = out
                do {
                    try process.run()
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    let text = String(decoding: data, as: UTF8.self)
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: text)
                    } else {
                        continuation.resume(throwing: ProviderError.other(
                            "\((executable as NSString).lastPathComponent) failed: \(text.prefix(200))"
                        ))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Only release assets served from this repository over HTTPS are ever downloaded.
    private static func isTrustedAsset(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/\(repo)/releases/download/")
    }

    static func isNewer(_ remote: String, than local: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let r = parts(remote), l = parts(local)
        for i in 0..<max(r.count, l.count) {
            let a = i < r.count ? r[i] : 0
            let b = i < l.count ? l[i] : 0
            if a != b { return a > b }
        }
        return false
    }
}
