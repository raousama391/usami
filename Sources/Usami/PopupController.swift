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

    init() {
        model.onLayoutChange = { [weak self] in self?.scheduleResize() }
        model.onExpand = { [weak self] in self?.scheduleCardPlacement() }
        model.onClose = { [weak self] in self?.hide() }
        model.onAccept = { [weak self] info, text in self?.accept(info, text) }
    }

    var isVisible: Bool { panel?.isVisible == true }

    func show(for selection: SelectionInfo) {
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

    func hide() {
        panel?.orderOut(nil)
        shownText = nil
        selection = nil
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

    private func scheduleResize() {
        DispatchQueue.main.async { [weak self] in self?.resize() }
    }

    private func scheduleCardPlacement() {
        DispatchQueue.main.async { [weak self] in self?.placeCard() }
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
}
