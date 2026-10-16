import AppKit

// `Usami --render-previews <dir>` renders the README screenshots and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--render-previews") {
    let directory = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : "."
    MainActor.assumeIsolated { renderReadmeImages(to: directory) }
    exit(0)
}

// `Usami --render-ui <dir>` snapshots the setup guide, home pages and menu bar popover in both themes.
if let flag = CommandLine.arguments.firstIndex(of: "--render-ui") {
    let directory = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : "."
    MainActor.assumeIsolated { renderUISnapshots(to: directory) }
    exit(0)
}

// `Usami --render-demo <dir> [--debug-frames]` renders the README demo GIF and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--render-demo") {
    let directory = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : "."
    let debug = CommandLine.arguments.contains("--debug-frames")
    let white = CommandLine.arguments.contains("--white-background")
    MainActor.assumeIsolated { renderDemo(to: directory, debug: debug, whiteBackground: white) }
    exit(0)
}

// `Usami --check-updates` prints whether a newer release exists; `Usami --update` also installs it.
if CommandLine.arguments.contains("--check-updates") || CommandLine.arguments.contains("--update") {
    let install = CommandLine.arguments.contains("--update")
    MainActor.assumeIsolated {
        _ = NSApplication.shared
        Task { @MainActor in
            let updater = Updater.shared
            await updater.check(userInitiated: true)
            print("current: \(updater.currentVersion)  state: \(updater.state)  selfInstall: \(updater.canSelfInstall)")
            if install, case .available = updater.state {
                await updater.install()   // quits this process once the helper has taken over
                print("install result: \(updater.state)")
            }
            exit(0)
        }
    }
    RunLoop.main.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
