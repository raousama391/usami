import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let monitor = SelectionMonitor()
    private let popup = PopupManager()
    private var trustTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        buildStatusItem()

        Updater.shared.isBusy = { [weak self] in self?.popup.isCardOpen ?? false }
        Updater.shared.start()

        monitor.onSelection = { [weak self] info in self?.popup.show(for: info) }
        monitor.onCleared = { [weak self] in self?.popup.selectionCleared() }

        let trusted = AXText.isTrusted()
        DebugLog.write("launch: accessibility trusted = \(trusted)")
        if !Settings.shared.onboarded {
            // First run: the setup guide walks through provider, sign-in and Accessibility.
            OnboardingWindowController.shared.show()
        } else if !trusted {
            _ = AXText.isTrusted(prompt: true)
            SettingsWindowController.shared.show()
        }
        if trusted {
            monitor.start()
        } else {
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
                if !enabled { self?.popup.hideAll() }
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
            button.image = makeStatusBarImage()
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(close: { [weak self] in self?.popover.performClose(nil) })
        )
        statusItem = item
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

}
