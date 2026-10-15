import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var statusItem: NSStatusItem?
    private let monitor = SelectionMonitor()
    private let popup = PopupController()
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        buildStatusItem()

        monitor.onSelection = { [weak self] info in self?.popup.show(for: info) }
        monitor.onCleared = { [weak self] in self?.popup.selectionCleared() }

        let trusted = AXText.isTrusted(prompt: true)
        DebugLog.write("launch: accessibility trusted = \(trusted)")
        if trusted {
            monitor.start()
        } else {
            SettingsWindowController.shared.show()
            trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                MainActor.assumeIsolated {
                    guard let self, AXText.isTrusted() else { return }
                    timer.invalidate()
                    DebugLog.write("trust granted at runtime — starting selection monitor")
                    self.monitor.start()
                }
            }
        }

        Settings.shared.$enabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] enabled in
                if !enabled { self?.popup.hide() }
                self?.statusItem?.button?.appearsDisabled = !enabled
            }
            .store(in: &cancellables)
    }

    // MARK: Menus

    /// Accessory apps have no menu bar of their own, so ⌘C/⌘V/⌘A/⌘X never reach text fields
    /// unless an Edit menu with those key equivalents exists.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Usami", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: Menu bar

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Usami")
        }

        let menu = NSMenu()
        let access = NSMenuItem(title: "Accessibility access", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        access.target = self
        menu.addItem(access)
        let toggle = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Usami", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleEnabled) {
            menuItem.state = Settings.shared.enabled ? .on : .off
        }
        if menuItem.action == #selector(openAccessibilitySettings) {
            let trusted = AXText.isTrusted()
            menuItem.title = trusted ? "Accessibility: granted ✓" : "⚠️ Fix Accessibility access…"
            menuItem.isEnabled = !trusted
            return !trusted
        }
        return true
    }

    @objc private func openAccessibilitySettings() {
        AXText.resetAndRequestAccess()
    }

    @objc private func toggleEnabled() { Settings.shared.enabled.toggle() }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
