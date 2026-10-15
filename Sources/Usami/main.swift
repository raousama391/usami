import AppKit

// `Usami --render-previews <dir>` renders the README screenshots and exits.
if let flag = CommandLine.arguments.firstIndex(of: "--render-previews") {
    let directory = CommandLine.arguments.count > flag + 1 ? CommandLine.arguments[flag + 1] : "."
    MainActor.assumeIsolated { renderReadmeImages(to: directory) }
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
