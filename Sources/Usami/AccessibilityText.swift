import AppKit
import ApplicationServices

struct SelectionInfo {
    let text: String
    let element: AXUIElement
    let rect: NSRect          // Cocoa screen coordinates
    let firstLineRect: NSRect? // bounds of the first selected character, used to align the trigger
    let isEditable: Bool
    let app: NSRunningApplication?
}

/// Thin wrapper over the macOS Accessibility API for reading and replacing the selection
/// in whatever app currently has focus.
enum AXText {
    static func isTrusted(prompt: Bool = false) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    /// Clears any stale Accessibility entry for this app (one that is listed but no longer matches
    /// this build's signature) and then shows the system prompt so a fresh, matching entry is created.
    static func resetAndRequestAccess() {
        let bundleID = Bundle.main.bundleIdentifier ?? "io.prodify.usami"
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DebugLog.write("tccutil reset Accessibility \(bundleID) → exit \(process.terminationStatus)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                _ = isTrusted(prompt: true)
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: Reading

    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &value) == .success,
           let value {
            return (value as! AXUIElement)
        }
        if let app = NSWorkspace.shared.frontmostApplication {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &value) == .success,
               let value {
                return (value as! AXUIElement)
            }
        }
        return nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    /// Screen rect of a character range, converted to Cocoa coordinates.
    static func bounds(of range: CFRange, in element: AXUIElement) -> NSRect? {
        var r = range
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &out
        ) == .success, let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func isSecure(_ element: AXUIElement) -> Bool {
        string(element, kAXSubroleAttribute as String) == "AXSecureTextField"
    }

    static func isEditable(_ element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        for attribute in [kAXSelectedTextAttribute, kAXValueAttribute] {
            if AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success, settable.boolValue {
                return true
            }
        }
        let role = string(element, kAXRoleAttribute as String) ?? ""
        return ["AXTextArea", "AXTextField", "AXComboBox"].contains(role)
    }

    /// Chromium / Electron apps only build their accessibility tree when asked.
    static func requestAccessibility(forPID pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    // MARK: Writing

    /// Replaces the current selection. Tries the Accessibility API first, then falls back to
    /// pasting through the pasteboard for apps that ignore AX writes.
    static func replaceSelection(of info: SelectionInfo, with text: String) {
        if AXUIElementSetAttributeValue(info.element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            usleep(80_000)
            if let value = string(info.element, kAXValueAttribute as String) {
                if value.contains(text) { return }
            } else {
                return
            }
        }
        if let app = info.app, !app.isActive {
            app.activate()
            usleep(150_000)
        }
        pasteViaPasteboard(text)
    }

    private static func pasteViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pasteboard.pasteboardItems ?? []).map { item in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            pasteboard.clearContents()
            for itemData in saved {
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                pasteboard.writeObjects([item])
            }
        }
    }
}
