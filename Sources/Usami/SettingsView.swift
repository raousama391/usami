import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingView(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Usami Settings"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var claude = ClaudeAuth.shared
    @ObservedObject private var codex = CodexAuth.shared

    @State private var trusted = AXText.isTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var pastedCode = ""
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show suggestions when I select text", isOn: $settings.enabled)
                Toggle("Also show for read-only text (copy only)", isOn: $settings.showForReadOnly)
                Picker("Trigger icon", selection: $settings.triggerStyle) {
                    ForEach(TriggerStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
                HStack {
                    Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(trusted ? .green : .orange)
                    Text(trusted ? "Accessibility access granted" : "Accessibility access needed to read your selection")
                    Spacer()
                    if !trusted {
                        Button("Fix…") { AXText.resetAndRequestAccess() }
                            .help("Clears the stale entry, then asks macOS for access again")
                    }
                }
            }

            Section("AI provider") {
                Picker("Use", selection: $settings.provider) {
                    ForEach(ProviderKind.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                if settings.provider == .claude { claudeSection } else { codexSection }
            }

            Section("Translate") {
                Picker("Default language", selection: $settings.translateTo) {
                    ForEach(Settings.languages, id: \.self) { Text($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
        .onReceive(timer) { _ in trusted = AXText.isTrusted() }
    }

    // MARK: Claude

    @ViewBuilder
    private var claudeSection: some View {
        Picker("Model", selection: $settings.claudeModel) {
            ForEach(Settings.claudeModels, id: \.self) { Text($0) }
        }

        if claude.isSignedIn {
            statusRow("Signed in with your Claude subscription", ok: true)
            Button("Sign out") { claude.signOut() }
        } else if claude.awaitingCode {
            Text("Approve access in the browser tab that just opened, then paste the code shown there.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Paste code here", text: $pastedCode)
            HStack {
                Button("Connect") {
                    Task { await claude.completeSignIn(pasted: pastedCode); pastedCode = "" }
                }
                .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty || claude.isWorking)
                Button("Cancel") { claude.cancelSignIn() }
                if claude.isWorking { ProgressView().controlSize(.small) }
            }
        } else {
            Text("Uses your Claude Pro/Max plan through the Claude Code CLI. If you're already logged in to `claude` in Terminal, it works without signing in here.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Sign in with Claude…") { claude.beginSignIn() }
        }
        if let error = claude.lastError {
            Text(error).font(.callout).foregroundStyle(.red)
        }
    }

    // MARK: ChatGPT

    @ViewBuilder
    private var codexSection: some View {
        Picker("Model", selection: $settings.codexModel) {
            ForEach(Settings.codexModels, id: \.self) { Text($0) }
        }

        switch codex.phase {
        case .waiting(let userCode, let url):
            Text("Enter this code on the page that just opened:")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Text(userCode)
                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(userCode, forType: .string)
                }
            }
            HStack {
                Button("Open page again") { NSWorkspace.shared.open(URL(string: url)!) }
                Button("Cancel") { codex.cancelSignIn() }
                ProgressView().controlSize(.small)
                Text("Waiting for approval…").font(.callout).foregroundStyle(.secondary)
            }
        case .idle:
            if codex.isSignedIn {
                statusRow("Signed in with your ChatGPT subscription", ok: true)
                Button("Sign out") { codex.signOut() }
            } else {
                Text("Uses your ChatGPT Plus/Pro plan via the Codex sign-in.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Sign in with ChatGPT…") { codex.beginSignIn() }
            }
        }
        if let error = codex.lastError {
            Text(error).font(.callout).foregroundStyle(.red)
        }
    }

    private func statusRow(_ text: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(ok ? .green : .red)
            Text(text)
        }
    }
}
