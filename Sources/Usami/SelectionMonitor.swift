import AppKit
import ApplicationServices

private func axObserverCallback(
    _ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<SelectionMonitor>.fromOpaque(refcon).takeUnretainedValue()
    DispatchQueue.main.async { monitor.scheduleCheck(after: 0.15) }
}

/// Watches for text selection changes in any app, the way a system-wide writing assistant does:
/// mouse-up events catch click/drag/double-click selections, and an AXObserver on the frontmost
/// app catches keyboard selections (shift+arrows, cmd+A).
final class SelectionMonitor {
    var onSelection: ((SelectionInfo) -> Void)?
    var onCleared: (() -> Void)?

    private var monitors: [Any] = []
    private var observer: AXObserver?
    private var observedPID: pid_t = 0
    private var pendingCheck: DispatchWorkItem?
    private var started = false

    func start() {
        guard !started else { return }
        started = true

        if let up = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] _ in
            self?.scheduleCheck(after: 0.12)
        }) { monitors.append(up) }

        if let down = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .scrollWheel],
            handler: { [weak self] _ in self?.onCleared?() }
        ) { monitors.append(down) }

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontAppChanged), name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if let front = NSWorkspace.shared.frontmostApplication { attach(to: front) }
    }

    @objc private func frontAppChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        attach(to: app)
    }

    private func attach(to app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier, pid != observedPID else { return }
        detach()

        AXText.requestAccessibility(forPID: pid)

        var created: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &created) == .success, let created else { return }
        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXSelectedTextChangedNotification, kAXFocusedUIElementChangedNotification] {
            AXObserverAddNotification(created, appElement, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        observedPID = pid
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        observedPID = 0
    }

    func scheduleCheck(after delay: TimeInterval) {
        pendingCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.checkSelection() }
        pendingCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func checkSelection() {
        guard Settings.shared.enabled else { return }
        guard AXText.isTrusted() else {
            DebugLog.write("check: NOT TRUSTED — Accessibility grant missing for this build")
            return
        }
        // Still dragging a selection; the mouse-up will trigger another check.
        guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let appName = front.bundleIdentifier ?? front.localizedName ?? "?"
        guard let element = AXText.focusedElement() else {
            DebugLog.write("check[\(appName)]: no focused element")
            onCleared?()
            return
        }
        guard !AXText.isSecure(element) else {
            DebugLog.write("check[\(appName)]: secure field, skipped")
            onCleared?()
            return
        }

        let role = AXText.string(element, kAXRoleAttribute as String) ?? "?"
        let selected = AXText.string(element, kAXSelectedTextAttribute as String) ?? ""
        guard selected.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3 else {
            DebugLog.write("check[\(appName)] role=\(role): selection too short/empty (\(selected.count) chars)")
            onCleared?()
            return
        }

        let editable = AXText.isEditable(element)
        guard editable || Settings.shared.showForReadOnly else {
            DebugLog.write("check[\(appName)] role=\(role): read-only, skipped")
            onCleared?()
            return
        }
        DebugLog.write("check[\(appName)] role=\(role): selection \(selected.count) chars, editable=\(editable) → show")

        var rect: NSRect?
        var firstLine: NSRect?
        if let range = AXText.selectedRange(element) {
            rect = AXText.bounds(of: range, in: element)
            firstLine = AXText.bounds(of: CFRange(location: range.location, length: 1), in: element)
        }
        let mouse = NSEvent.mouseLocation
        let anchor = rect ?? NSRect(x: mouse.x, y: mouse.y, width: 1, height: 1)

        onSelection?(SelectionInfo(
            text: selected, element: element, rect: anchor, firstLineRect: firstLine,
            isEditable: editable, app: front
        ))
    }
}
