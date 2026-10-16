import AppKit
import SwiftUI

/// Draws each screen in an offscreen window and saves it as a PNG, for checking the layout in
/// light and dark without clicking through the app. Vibrancy renders flat in these snapshots.
@MainActor
func renderUISnapshots(to directory: String) {
    _ = NSApplication.shared
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    var screens: [(String, AnyView, NSSize)] = []
    for step in 0..<5 {
        screens.append(("setup-\(step)", AnyView(OnboardingView(onFinish: {}, initialStep: step)), NSSize(width: 900, height: 600)))
    }
    for page in HomePage.allCases {
        let navigation = HomeNavigation()
        navigation.page = page
        screens.append(("home-\(page.rawValue)", AnyView(SettingsView(navigation: navigation)), NSSize(width: 960, height: 660)))
    }
    let info = SelectionInfo(
        text: "hey team, i think we shoud move the meeting to thrusday becuase alot of people is out",
        element: AXUIElementCreateSystemWide(), rect: .zero, firstLineRect: nil, isEditable: true, app: nil
    )
    for (name, request, result) in [
        ("card-custom-empty", "", ""),
        ("card-custom-result", "make it more polite", "Hi team, I'd suggest moving the meeting to Thursday, as quite a few people will be out."),
    ] {
        let model = PopupModel()
        model.configureForPreview(selection: info, result: result, customRequest: request)
        screens.append((name, AnyView(PopupPreviewParts.card(model).background(Theme.window)), NSSize(width: 396, height: 250)))
    }
    screens.append(("menubar", AnyView(MenuBarView(close: {}).background(Theme.window)), NSSize(width: 300, height: 340)))

    for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        let appearance = NSAppearance(named: name)
        for (title, view, size) in screens {
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = appearance
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            let path = (directory as NSString).appendingPathComponent("\(title)-\(suffix).png")
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("wrote \(path)")
        }
    }
}
