import AppKit
import ServiceManagement
import SwiftUI

enum HomePage: String, CaseIterable, Identifiable {
    case home, ai, translate, updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .ai: "AI model"
        case .translate: "Translate"
        case .updates: "Updates"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .ai: "sparkles"
        case .translate: "character.bubble"
        case .updates: "arrow.triangle.2.circlepath"
        }
    }
}

/// Navigation state shared between the window controller and the view.
@MainActor
final class HomeNavigation: ObservableObject {
    @Published var page: HomePage = .home
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private let navigation = HomeNavigation()

    func show(page: HomePage? = nil) {
        if let page { navigation.page = page }
        if window == nil {
            let window = makeAppWindow(
                size: NSSize(width: 960, height: 660), title: "Usami",
                content: SettingsView(navigation: navigation)
            )
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var navigation: HomeNavigation
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                Group {
                    switch navigation.page {
                    case .home: HomePageView(navigation: navigation)
                    case .ai: AIPageView()
                    case .translate: TranslatePageView()
                    case .updates: UpdatesPageView()
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 46)
                .padding(.bottom, 32)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Theme.window)
        }
        .frame(width: 960, height: 660)
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 11) {
                SparkleBadge(size: 32)
                Text("Usami").font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 24)

            ForEach(HomePage.allCases) { page in
                SidebarRow(page: page, active: navigation.page == page) {
                    withAnimation(.easeOut(duration: 0.18)) { navigation.page = page }
                }
            }

            Spacer()

            Button { navigation.page = .updates } label: {
                HStack(spacing: 10) {
                    Circle().fill(updateDot).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("v\(updater.currentVersion)").font(.system(size: 12.5, weight: .semibold))
                        Text(updateLine).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.chip))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 56)
        .padding(.bottom, 18)
        .frame(width: 232)
        .frame(maxHeight: .infinity)
        .background(SidebarMaterial())
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private var updateDot: Color {
        if case .available = updater.state { return Theme.accent }
        return Theme.switchOn
    }

    private var updateLine: String {
        switch updater.state {
        case .available(let version): "v\(version) available"
        case .checking: "Checking…"
        case .downloading, .installing: "Updating…"
        default: settings.updateMode == .off ? "Checks are off" : "Up to date"
        }
    }
}

private struct SidebarRow: View {
    var page: HomePage
    var active: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: page.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(page.title).font(.system(size: 14, weight: active ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(active ? Theme.accent : (hovering ? Theme.text : Theme.muted))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(active ? Theme.soft : (hovering ? Theme.chip : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Home

private struct HomePageView: View {
    @ObservedObject var navigation: HomeNavigation
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var claude = ClaudeAuth.shared
    @ObservedObject private var codex = CodexAuth.shared
    @ObservedObject private var updater = Updater.shared
    @State private var trusted = AXText.isTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    private var connected: Bool {
        settings.provider == .claude ? claude.isSignedIn : codex.isSignedIn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            if !trusted { accessBanner }
            tiles
            HStack(alignment: .top, spacing: 14) {
                triggerCard
                preferencesCard
            }
        }
        .onReceive(poll) { _ in trusted = AXText.isTrusted() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    LiveDot(color: settings.enabled ? Theme.ok : Theme.muted, live: settings.enabled)
                    Text(settings.enabled ? "On" : "Paused").font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(settings.enabled ? Theme.ok : Theme.muted)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Capsule().fill(settings.enabled ? Theme.okSoft : Theme.chip))

                Text(settings.enabled ? "Usami is ready." : "Usami is paused.")
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.8)
                    .padding(.top, 12)
                Text("Select text in any app and click the sparkle that appears.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 5)
            }
            Spacer()
            PillSwitch(isOn: $settings.enabled, width: 58, label: "Enable Usami")
        }
        .animation(.easeOut(duration: 0.2), value: settings.enabled)
    }

    private var accessBanner: some View {
        HStack(spacing: 14) {
            IconTile(systemName: "exclamationmark.triangle.fill", tint: Theme.warn, fill: Theme.warnSoft)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility access is off").font(.system(size: 14, weight: .semibold))
                Text("Usami can't see your selection until you switch it on in System Settings.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }
            Spacer()
            Button("Fix…") { AXText.resetAndRequestAccess() }.buttonStyle(PrimaryButtonStyle(compact: true))
        }
        .card(radius: 16, padding: 14)
    }

    private var tiles: some View {
        HStack(spacing: 14) {
            Tile {
                HStack(spacing: 10) {
                    ProviderMark(provider: settings.provider, size: 22)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chip))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(settings.provider.displayName).font(.system(size: 15, weight: .semibold))
                        Text(settings.currentModel).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                }
            } footer: {
                if connected || settings.provider == .claude {
                    StatusChip(text: connected ? "Connected" : "Not signed in", icon: connected ? "checkmark" : nil,
                               tone: connected ? .ok : .neutral)
                } else {
                    StatusChip(text: "Not connected", tone: .warn)
                }
                Spacer()
                Button("Change") { navigation.page = .ai }
                    .buttonStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }

            Tile {
                HStack(spacing: 10) {
                    IconTile(systemName: trusted ? "checkmark.shield" : "exclamationmark.shield",
                             tint: trusted ? Theme.ok : Theme.warn, fill: trusted ? Theme.okSoft : Theme.warnSoft, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Accessibility").font(.system(size: 15, weight: .semibold))
                        Text(trusted ? "Granted" : "Needed").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                }
            } footer: {
                Text(trusted ? "Updates keep this permission." : "Switch Usami on to start.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
            }

            Tile {
                HStack(spacing: 10) {
                    IconTile(systemName: "arrow.triangle.2.circlepath", size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Updates").font(.system(size: 15, weight: .semibold))
                        Text(updateLabel).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    }
                }
            } footer: {
                if case .available(let version) = updater.state {
                    Button("Update to v\(version)") { Task { await updater.install() } }
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                } else {
                    Button("Check now") { Task { await updater.check(userInitiated: true) } }
                        .buttonStyle(SoftButtonStyle(compact: true))
                        .disabled(updater.state == .checking)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var updateLabel: String {
        switch updater.state {
        case .available(let version): "v\(version) is ready"
        case .checking: "Checking…"
        case .downloading: "Downloading…"
        case .installing: "Installing…"
        case .failed: "Couldn't check"
        default: "v\(updater.currentVersion) · up to date"
        }
    }

    private var triggerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Trigger icon").font(.system(size: 15, weight: .semibold))
            Text("Appears to the left of your selection.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 3)
            HStack(spacing: 12) {
                ForEach(TriggerStyle.allCases.reversed()) { style in
                    TriggerOption(style: style, selected: settings.triggerStyle == style) {
                        settings.triggerStyle = style
                    }
                }
            }
            .padding(.top, 16)
            Text("It pops in, ripples, then settles so it never nags.")
                .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 18, padding: 20)
    }

    private var preferencesCard: some View {
        VStack(spacing: 0) {
            PrefRow(title: "Show for read-only text", detail: "Copy only, when you can't edit the text.") {
                PillSwitch(isOn: $settings.showForReadOnly, label: "Show for read-only text")
            }
            Divider().overlay(Theme.line)
            PrefRow(title: "Launch at login", detail: "Always ready after a restart.") {
                PillSwitch(isOn: $launchAtLogin, label: "Launch at login")
                    .onChange(of: launchAtLogin) { _, on in
                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                    }
            }
            Divider().overlay(Theme.line)
            PrefRow(title: "Translate to", detail: nil) {
                Menu {
                    ForEach(Settings.languages, id: \.self) { language in
                        Button(language) { settings.translateTo = language }
                    }
                } label: {
                    HStack(spacing: 7) {
                        Text(settings.translateTo).font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            Divider().overlay(Theme.line)
            PrefRow(title: "Setup guide", detail: "Walk through the first-run steps again.") {
                Button("Open") { OnboardingWindowController.shared.show() }
                    .buttonStyle(SoftButtonStyle(compact: true))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
    }
}

private struct Tile<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            content
            Spacer(minLength: 0)
            HStack { footer }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.card)
                .shadow(color: .black.opacity(hovering ? 0.08 : 0), radius: 14, y: 6)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
        .offset(y: hovering ? -2 : 0)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }
}

private struct PrefRow<Control: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                if let detail {
                    Text(detail).font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                }
            }
            Spacer()
            control
        }
        .padding(.vertical, 12)
    }
}

private struct TriggerOption: View {
    var style: TriggerStyle
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                ZStack {
                    if style == .solid {
                        SparkleBadge(size: 36)
                    } else {
                        Circle().fill(Theme.window)
                        Circle().strokeBorder(AppPalette.blue, lineWidth: 1.75)
                        SparkleGlyph(color: AppPalette.blue).frame(width: 21, height: 21)
                    }
                }
                .frame(width: 36, height: 36)
                .shadow(color: .black.opacity(style == .solid ? 0 : 0.15), radius: 4, y: 2)
                Text(style.title).font(.system(size: 13, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.chip))
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5)
            )
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Theme.soft).padding(-4).opacity(selected ? 1 : 0)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
    }
}

/// A status dot with a soft ping while live.
private struct LiveDot: View {
    var color: Color
    var live: Bool
    @State private var ping = false

    var body: some View {
        ZStack {
            if live {
                Circle().fill(color)
                    .scaleEffect(ping ? 2.4 : 1)
                    .opacity(ping ? 0 : 0.5)
                    .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false), value: ping)
            }
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onAppear { ping = true }
    }
}

// MARK: - AI model

private struct AIPageView: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "AI model", subtitle: "Use the subscription you already pay for. Switch any time.")
            HStack(spacing: 16) {
                ForEach(ProviderKind.allCases) { kind in
                    ProviderCard(kind: kind, selected: settings.provider == kind) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.provider = kind }
                    }
                }
            }
            .padding(.top, 24)
            Text("Model").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 24)
            ModelPills(provider: settings.provider).padding(.top, 10)
            Text("Account").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 26)
            ProviderSignInPanel(provider: settings.provider).padding(.top, 10)
            if settings.provider == .claude {
                Text("Already logged in to the claude command in Terminal? Usami works without signing in here.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted).padding(.top, 12)
            }
        }
    }
}

// MARK: - Translate

private struct TranslatePageView: View {
    @ObservedObject private var settings = Settings.shared
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Translate", subtitle: "The language Translate uses unless you pick another in the card.")
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Settings.languages, id: \.self) { language in
                    let on = settings.translateTo == language
                    Button { settings.translateTo = language } label: {
                        HStack {
                            Text(language).font(.system(size: 13.5, weight: on ? .semibold : .medium))
                            Spacer()
                            if on { Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)) }
                        }
                        .foregroundStyle(on ? Theme.accent : Theme.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Theme.soft : Theme.card))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(on ? Theme.accent : Theme.line))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 24)
            .animation(.easeOut(duration: 0.15), value: settings.translateTo)
        }
    }
}

// MARK: - Updates

private struct UpdatesPageView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(title: "Updates", subtitle: "New versions install without asking for your password.")
            HStack(spacing: 16) {
                SparkleBadge(size: 48)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Usami \(updater.currentVersion)").font(.system(size: 17, weight: .semibold))
                    status
                }
                Spacer()
                if case .available(let version) = updater.state {
                    Button(updater.canSelfInstall ? "Update to v\(version)" : "View v\(version)") {
                        Task { await updater.install() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                } else {
                    Button("Check now") { Task { await updater.check(userInitiated: true) } }
                        .buttonStyle(SoftButtonStyle())
                        .disabled(updater.state == .checking || updater.state == .downloading || updater.state == .installing)
                }
            }
            .card(radius: 18, padding: 22)
            .padding(.top, 24)

            Text("When a new version is out").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 26)
            HStack(spacing: 3) {
                ForEach(UpdateMode.allCases) { mode in
                    let on = settings.updateMode == mode
                    Button { settings.updateMode = mode } label: {
                        Text(mode.title)
                            .font(.system(size: 13, weight: on ? .semibold : .medium))
                            .foregroundStyle(on ? Theme.text : Theme.muted)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(on ? Theme.card : .clear)
                                    .shadow(color: .black.opacity(on ? 0.15 : 0), radius: 2, y: 1)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chip))
            .padding(.top, 10)
            .animation(.easeOut(duration: 0.15), value: settings.updateMode)

            if !updater.canSelfInstall {
                Text("This copy isn't in your Applications folder, so it can't update itself. Install with the one-line installer to enable updates.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 16)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch updater.state {
        case .idle:
            Text(settings.updateMode == .off ? "Automatic checks are off" : "Checks every few hours")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        case .checking:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Checking…") }
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        case .upToDate:
            StatusChip(text: "Up to date", icon: "checkmark")
        case .available(let version):
            StatusChip(text: "v\(version) available", icon: "arrow.up", tone: .accent)
        case .downloading:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Downloading…") }
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        case .installing:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Installing, restarting…") }
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        case .failed(let message):
            Text(message).font(.system(size: 12.5)).foregroundStyle(.red).lineLimit(2)
        }
    }
}

private struct PageHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 28, weight: .bold)).tracking(-0.7)
            Text(subtitle).font(.system(size: 14.5)).foregroundStyle(Theme.muted)
        }
    }
}
