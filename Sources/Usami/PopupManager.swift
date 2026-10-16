import AppKit

/// Owns every popup on screen. One "live" controller reacts to the current selection and shows the
/// trigger; the moment its card is opened it is pinned to the window the text came from and a fresh
/// live controller takes over, so a card open in one app never blocks the trigger in another.
@MainActor
final class PopupManager {
    private var live: PopupController
    private var pinned: [PopupController] = []
    private var suppressUntil = Date.distantPast

    /// True while at least one card is open (used to hold back app updates).
    var isCardOpen: Bool { !pinned.isEmpty }

    init() {
        live = PopupController()
        wire(live)
    }

    func show(for selection: SelectionInfo) {
        guard Date() >= suppressUntil else { return }
        // The same text in the same app already has a card; don't offer a second trigger for it.
        let pid = selection.app?.processIdentifier ?? 0
        if pinned.contains(where: { $0.hasCard(for: selection.text, pid: pid) }) { return }
        live.show(for: selection)
    }

    func selectionCleared() {
        live.selectionCleared()
    }

    /// Closes everything (the app being disabled).
    func hideAll() {
        live.hide()
        for controller in pinned { controller.hide() }
        pinned.removeAll()
    }

    // MARK: Private

    private func wire(_ controller: PopupController) {
        controller.onCardOpened = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.pin(controller)
        }
        controller.onHidden = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.pinned.removeAll { $0 === controller }
        }
        controller.onAccepted = { [weak self] in
            self?.suppressUntil = Date().addingTimeInterval(1.0)
        }
    }

    /// Detaches an opened card from the selection-driven slot and hands that slot to a new controller.
    private func pin(_ controller: PopupController) {
        guard controller === live else { return }
        pinned.append(controller)
        live = PopupController()
        wire(live)
    }
}
