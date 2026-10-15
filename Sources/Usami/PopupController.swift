import AppKit
import SwiftUI

/// Floating, non-activating panel — it never steals focus from the app the user is typing in,
/// so the original selection stays intact until we replace it.
private final class PopupPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupController {
    private let model = PopupModel()
    private var panel: PopupPanel?
    private var hosting: NSHostingView<PopupRootView>?
    private var suppressUntil = Date.distantPast
    private var shownText: String?
    private var selection: SelectionInfo?
    /// Whether the expanded card sits below the selection (top edge fixed) or above it (bottom edge fixed).
    private var cardBelow = true

    // Sticky card: once opened, only the ✕ (or Accept) closes it, and it follows its source window.
    private var cardOpen = false
    private var sourcePID: pid_t = 0
    private var sourceWindow: AXUIElement?
    private var offsetFromWindow = CGSize.zero
    private var trackTimer: Timer?

    init() {
        model.onLayoutChange = { [weak self] in self?.scheduleResize() }
        model.onExpand = { [weak self] in self?.cardOpened() }
        model.onClose = { [weak self] in self?.hide() }
        model.onAccept = { [weak self] info, text in self?.accept(info, text) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(for selection: SelectionInfo) {
        // An open card is pinned: new selections never replace or dismiss it.
        guard !cardOpen else { return }
        guard Date() >= suppressUntil else { return }
        if isVisible, shownText == selection.text { return }

        ensurePanel()
        shownText = selection.text
        self.selection = selection
        cardBelow = true
        model.reset(selection: selection)

        guard let panel else { return }
        let size = PopupMetrics.triggerSize
        // Left of the selection, vertically centred on its first line.
        let line = selection.firstLineRect ?? selection.rect
        let origin = NSPoint(
            x: selection.rect.minX - size.width - 2,
            y: line.midY - size.height / 2
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        clampToScreen()
        panel.orderFrontRegardless()
    }

    /// Called when the selection goes away or the user clicks elsewhere. Only the small trigger
    /// reacts to that — an open card stays until its ✕ is pressed.
    func selectionCleared() {
        guard !cardOpen else { return }
        hide()
    }

    /// Closes everything (✕, Accept, or the app being disabled).
    func hide() {
        stopTracking()
        cardOpen = false
        panel?.orderOut(nil)
        shownText = nil
        selection = nil
        sourceWindow = nil
    }

    // MARK: Private

    private func accept(_ info: SelectionInfo, _ text: String) {
        suppressUntil = Date().addingTimeInterval(1.0)
        hide()
        DispatchQueue.global(qos: .userInitiated).async {
            AXText.replaceSelection(of: info, with: text)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = PopupPanel(
            contentRect: NSRect(origin: .zero, size: PopupMetrics.triggerSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = nil   // follow the system light/dark theme

        let hosting = NSHostingView(rootView: PopupRootView(model: model))
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
    }

    // MARK: Card lifecycle

    private func cardOpened() {
        cardOpen = true
        sourcePID = selection?.app?.processIdentifier ?? 0
        if let element = selection?.element, sourcePID != 0 {
            sourceWindow = AXText.window(containing: element, pid: sourcePID)
        } else {
            sourceWindow = nil
        }
        DispatchQueue.main.async { [weak self] in
            self?.placeCard()
            self?.startTracking()
        }
    }

    private func scheduleResize() {
        DispatchQueue.main.async { [weak self] in self?.resize() }
    }

    /// Opens the card just below the selection (or above it when there's no room), left-aligned with it.
    private func placeCard() {
        guard let panel, let hosting, let selection, model.phase == .card else { return }
        let size = hosting.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let screen = NSScreen.screens.first { $0.frame.intersects(selection.rect.insetBy(dx: -1, dy: -1)) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero

        var y = selection.rect.minY - 4 - size.height
        cardBelow = true
        if y < visible.minY + 8 {
            y = selection.rect.maxY + 4
            cardBelow = false
        }
        let x = selection.rect.minX - 8
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        clampToScreen()
        captureWindowOffset()
    }

    private func resize() {
        guard let panel, let hosting, panel.isVisible else { return }
        let size = model.phase == .card ? hosting.fittingSize : PopupMetrics.triggerSize
        guard size.width > 0, size.height > 0 else { return }
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        if !(model.phase == .card && !cardBelow) {
            frame.origin.y = top - size.height
        }
        panel.setFrame(frame, display: true)
        clampToScreen()
        captureWindowOffset()
    }

    private func clampToScreen() {
        guard let panel else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, visible.minX + 4), visible.maxX - frame.width - 4)
        frame.origin.y = min(max(frame.origin.y, visible.minY + 4), visible.maxY - frame.height - 4)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    // MARK: Following the source window

    /// Remembers where the card sits relative to its window's top-left so it can follow the window.
    private func captureWindowOffset() {
        guard cardOpen, let panel, let window = sourceWindow,
              let point = AXText.windowPosition(window).point else { return }
        let topLeft = AXText.cocoaPoint(fromAX: point)
        offsetFromWindow = CGSize(
            width: panel.frame.origin.x - topLeft.x,
            height: panel.frame.origin.y - topLeft.y
        )
    }

    private func startTracking() {
        stopTracking()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackWindow() }
        }
        RunLoop.main.add(timer, forMode: .common)
        trackTimer = timer
    }

    private func stopTracking() {
        trackTimer?.invalidate()
        trackTimer = nil
    }

    private func trackWindow() {
        guard cardOpen, let panel else { return }

        // The source window is gone — nothing left to stick to.
        if let window = sourceWindow, AXText.windowPosition(window).invalid {
            hide()
            return
        }

        // Only show the card while its own window is the one in front.
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        var sourceInFront = frontPID == sourcePID || frontPID == ProcessInfo.processInfo.processIdentifier
        if sourceInFront, frontPID == sourcePID, let window = sourceWindow {
            sourceInFront = AXText.isFocusedWindow(window, pid: sourcePID) && !AXText.isMinimized(window)
        }
        guard sourceInFront else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }

        guard let window = sourceWindow, let point = AXText.windowPosition(window).point else { return }
        let topLeft = AXText.cocoaPoint(fromAX: point)
        let desired = NSPoint(x: topLeft.x + offsetFromWindow.width, y: topLeft.y + offsetFromWindow.height)
        if abs(desired.x - panel.frame.origin.x) > 0.5 || abs(desired.y - panel.frame.origin.y) > 0.5 {
            panel.setFrameOrigin(desired)
        }
    }
}
