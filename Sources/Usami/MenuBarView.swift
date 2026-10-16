import AppKit
import SwiftUI

/// Content of the menu bar popover: on/off, provider and model, and the usual app commands.
struct MenuBarView: View {
    var close: () -> Void

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = Updater.shared
    @State private var trusted = AXText.isTrusted()
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            if !trusted { accessWarning }
            aiSection
            Divider().overlay(Theme.line)
            VStack(spacing: 0) {
                if trusted {
                    MenuRow(title: "Accessibility", icon: "checkmark", iconTint: Theme.ok, trailing: "Granted", action: nil)
                }
                MenuRow(title: "Settings…", trailing: "⌘,") { open { SettingsWindowController.shared.show() } }
                    .keyboardShortcut(",", modifiers: .command)
                updateRow
                MenuRow(title: "Quit Usami", trailing: "⌘Q") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(6)
        }
        .frame(width: 300)
        .foregroundStyle(Theme.text)
        .onReceive(poll) { _ in trusted = AXText.isTrusted() }
    }

    private var header: some View {
        HStack(spacing: 11) {
            SparkleBadge(size: 34, glow: false)
            VStack(alignment: .leading, spacing: 1) {
                Text("Usami").font(.system(size: 14.5, weight: .bold))
                Text(settings.enabled ? "On" : "Paused")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(settings.enabled ? Theme.ok : Theme.muted)
            }
            Spacer()
            PillSwitch(isOn: $settings.enabled, width: 42, label: "Enable Usami")
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var accessWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
            Text("Accessibility access needed").font(.system(size: 12.5, weight: .medium))
            Spacer()
            Button("Fix…") { AXText.resetAndRequestAccess(); close() }
                .buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.warnSoft))
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AI")
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 2)
            HStack(spacing: 3) {
                ForEach(ProviderKind.allCases) { kind in
                    let on = settings.provider == kind
                    Button { settings.provider = kind } label: {
                        HStack(spacing: 7) {
                            ProviderMark(provider: kind, size: 15)
                            Text(kind.shortName).font(.system(size: 13, weight: on ? .semibold : .medium))
                        }
                        .foregroundStyle(on ? Theme.text : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(on ? Theme.card : .clear)
                                .shadow(color: .black.opacity(on ? 0.18 : 0), radius: 2, y: 1)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chip))
            .animation(.easeOut(duration: 0.15), value: settings.provider)

            HStack {
                Text("Model").font(.system(size: 13)).foregroundStyle(Theme.muted)
                Spacer()
                Menu {
                    ForEach(settings.provider.models, id: \.self) { model in
                        Button(model) { settings.currentModel = model }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(settings.currentModel).font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(Theme.text)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 2)
            .padding(.top, 3)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var updateRow: some View {
        switch updater.state {
        case .available(let version):
            MenuRow(title: "Update to v\(version)…", trailing: "New", trailingTint: Theme.accent) {
                Task { await updater.install() }
                close()
            }
        case .checking, .downloading, .installing:
            MenuRow(title: "Updating…", action: nil)
        default:
            MenuRow(title: "Check for updates…") {
                open { SettingsWindowController.shared.show(page: .updates) }
                Task { await updater.check(userInitiated: true) }
            }
        }
    }

    private func open(_ action: () -> Void) {
        close()
        action()
    }
}

private struct MenuRow: View {
    var title: String
    var icon: String?
    var iconTint: Color = Theme.muted
    var trailing: String?
    var trailingTint: Color = Theme.muted
    var action: (() -> Void)?
    @State private var hovering = false

    var body: some View {
        Button { action?() } label: {
            HStack(spacing: 9) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(iconTint)
                }
                Text(title).font(.system(size: 13))
                Spacer()
                if let trailing {
                    Text(trailing).font(.system(size: 12, weight: trailingTint == Theme.muted ? .regular : .semibold))
                        .foregroundStyle(trailingTint)
                }
            }
            .foregroundStyle(action == nil && icon == nil ? Theme.muted : Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering && action != nil ? Theme.soft : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .onHover { hovering = $0 }
    }
}

/// The menu bar icon: the app's sparkles as a template image so it tints with the menu bar.
@MainActor
func makeStatusBarImage() -> NSImage {
    let renderer = ImageRenderer(content: SparkleGlyph(color: .black).frame(width: 17, height: 17))
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    let image = renderer.nsImage ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Usami")!
    image.isTemplate = true
    image.accessibilityDescription = "Usami"
    return image
}
