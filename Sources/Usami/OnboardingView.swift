import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let window = makeAppWindow(
                size: NSSize(width: 900, height: 600), title: "Set up Usami",
                content: OnboardingView(onFinish: { [weak self] in self?.finish() })
            )
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        Settings.shared.onboarded = true
        window?.close()
    }
}

private enum SetupStep: Int, CaseIterable {
    case welcome, provider, signIn, access, done

    var title: String {
        switch self {
        case .welcome: "Welcome"
        case .provider: "Choose your AI"
        case .signIn: "Sign in"
        case .access: "Allow access"
        case .done: "All set"
        }
    }

    var hint: String {
        switch self {
        case .welcome: "Meet Usami"
        case .provider: "Claude or ChatGPT"
        case .signIn: "Use your plan"
        case .access: "One macOS switch"
        case .done: "Try it out"
        }
    }
}

struct OnboardingView: View {
    var onFinish: () -> Void

    init(onFinish: @escaping () -> Void, initialStep: Int = 0) {
        self.onFinish = onFinish
        _step = State(initialValue: SetupStep(rawValue: initialStep) ?? .welcome)
    }

    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var claude = ClaudeAuth.shared
    @ObservedObject private var codex = CodexAuth.shared
    @State private var step: SetupStep
    @State private var trusted = AXText.isTrusted()
    @State private var usesCLI = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isSignedIn: Bool {
        settings.provider == .claude ? (claude.isSignedIn || usesCLI) : codex.isSignedIn
    }

    private var canContinue: Bool {
        switch step {
        case .signIn: isSignedIn
        case .access: trusted
        default: true
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            rail
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    page.id(step)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 12)),
                            removal: .opacity
                        ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 52)
                .padding(.top, 58)
                footer
            }
            .frame(maxWidth: .infinity)
            .background(Theme.window)
        }
        .frame(width: 900, height: 600)
        .foregroundStyle(Theme.text)
        .ignoresSafeArea()
        .onReceive(poll) { _ in
            if step == .access { trusted = AXText.isTrusted() }
        }
    }

    // MARK: Rail

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                SparkleBadge(size: 32)
                Text("Usami").font(.system(size: 17, weight: .bold))
            }
            .padding(.bottom, 36)

            ForEach(SetupStep.allCases, id: \.self) { item in
                stepRow(item)
            }

            Spacer()
            Text("Takes about a minute. You only do this once, updates keep your access.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26)
        .padding(.top, 60)
        .padding(.bottom, 26)
        .frame(width: 250)
        .frame(maxHeight: .infinity)
        .background(SidebarMaterial())
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    private func stepRow(_ item: SetupStep) -> some View {
        let done = item.rawValue < step.rawValue
        let active = item == step
        return HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    if done {
                        Circle().fill(AppPalette.button)
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
                    } else if active {
                        Circle().fill(Theme.soft).padding(-5)
                        Circle().strokeBorder(Theme.accent, lineWidth: 2)
                        Text("\(item.rawValue + 1)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.accent)
                    } else {
                        Circle().strokeBorder(Theme.line, lineWidth: 1.5)
                        Text("\(item.rawValue + 1)").font(.system(size: 12.5, weight: .bold)).foregroundStyle(Theme.faint)
                    }
                }
                .frame(width: 28, height: 28)
                if item != SetupStep.allCases.last {
                    Capsule()
                        .fill(done ? AnyShapeStyle(AppPalette.button) : AnyShapeStyle(Theme.line))
                        .frame(width: 2)
                        .padding(.vertical, 6)
                }
            }
            .frame(height: 62, alignment: .top)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14.5, weight: active ? .bold : .medium))
                    .foregroundStyle(active || done ? Theme.text : Theme.muted)
                Text(item.hint).font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            .padding(.top, 4)
        }
        .animation(.easeOut(duration: 0.25), value: step)
    }

    // MARK: Pages

    @ViewBuilder
    private var page: some View {
        switch step {
        case .welcome: welcome
        case .provider: providerPage
        case .signIn: signInPage
        case .access: accessPage
        case .done: donePage
        }
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.accent)
    }

    private func heading(_ text: String) -> some View {
        Text(text).font(.system(size: 30, weight: .bold)).tracking(-0.6)
    }

    private func lede(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(3)
            .foregroundStyle(Theme.muted)
            .frame(maxWidth: 480, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            PulsingBadge(size: 84).padding(.bottom, 26)
            Text("Write better, anywhere you type.")
                .font(.system(size: 36, weight: .bold))
                .tracking(-1)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            lede("Select some text in any app. Usami pops up next to it so you can improve, rephrase or translate it in one click.")
                .padding(.top, 14)
            VStack(alignment: .leading, spacing: 14) {
                feature("macwindow", "Works in Slack, WhatsApp, Notes, your browser and more")
                feature("lock", "Only the text you pick is sent, only to the AI you choose")
                feature("square.grid.2x2", "Open cards in several apps at once")
            }
            .padding(.top, 28)
        }
    }

    private func feature(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 13) {
            IconTile(systemName: icon, size: 34)
            Text(text).font(.system(size: 14.5))
        }
    }

    private var providerPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Step 1 of 3")
            heading("Which AI should Usami use?").padding(.top, 10)
            lede("Use the subscription you already pay for. You can switch any time from the menu bar.").padding(.top, 10)
            HStack(spacing: 16) {
                ForEach(ProviderKind.allCases) { kind in
                    ProviderCard(kind: kind, selected: settings.provider == kind) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settings.provider = kind }
                    }
                }
            }
            .padding(.top, 26)
            Text("Model").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.muted).padding(.top, 24)
            ModelPills(provider: settings.provider).padding(.top, 10)
        }
    }

    private var signInPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Step 2 of 3")
            heading("Connect \(settings.provider.displayName)").padding(.top, 10)
            lede(settings.provider == .claude
                 ? "A browser tab opens so you can approve access, then paste the code it shows."
                 : "A browser page opens with a short code. Approve it there and Usami connects on its own.")
                .padding(.top, 10)
            ProviderSignInPanel(provider: settings.provider)
                .frame(maxWidth: 560)
                .padding(.top, 26)
            if settings.provider == .claude && !claude.isSignedIn {
                Toggle(isOn: $usesCLI) {
                    Text("I'm already logged in to the claude command in Terminal")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .toggleStyle(.checkbox)
                .padding(.top, 16)
            }
            Label("Your sign-in stays on this Mac. Updating Usami never asks for your password.", systemImage: "lock")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .padding(.top, 16)
        }
    }

    private var accessPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("Step 3 of 3")
            heading("Let Usami see your selection").padding(.top, 10)
            lede("macOS needs your OK before an app can read selected text. Open Privacy and Security, then switch Usami on under Accessibility.")
                .padding(.top, 10)
            VStack(spacing: 0) {
                Text("System Settings · Privacy and Security · Accessibility")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.chip)
                Divider().overlay(Theme.line)
                HStack(spacing: 14) {
                    SparkleBadge(size: 38, glow: false)
                    Text("Usami").font(.system(size: 15, weight: .semibold))
                    Spacer()
                    if trusted {
                        StatusChip(text: "Access granted", icon: "checkmark")
                    } else {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting for the switch…").font(.system(size: 12.5)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.line))
            .frame(maxWidth: 560)
            .padding(.top, 26)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: trusted)

            if !trusted {
                Button("Open System Settings") { AXText.resetAndRequestAccess() }
                    .buttonStyle(SoftButtonStyle())
                    .padding(.top, 16)
            }
        }
    }

    private var donePage: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: "checkmark")
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(Theme.ok)
                .frame(width: 46, height: 46)
                .background(Circle().fill(Theme.okSoft))
            heading("You're all set.").padding(.top, 18)
            lede("Select any text and look for the sparkle on its left. Here is what you will see.").padding(.top, 10)
            SelectionDemo(provider: settings.provider, model: settings.currentModel)
                .padding(.top, 24)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                ForEach(SetupStep.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item == step ? AnyShapeStyle(AppPalette.button) : AnyShapeStyle(Theme.line))
                        .frame(width: item == step ? 22 : 6, height: 6)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: step)
            Spacer()
            if step == .welcome {
                Button("Skip setup", action: onFinish)
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, 6)
            }
            if step != .welcome && step != .done {
                Button("Back") { go(-1) }.buttonStyle(SoftButtonStyle())
            }
            Button(nextLabel) {
                if step == .done { onFinish() } else { go(1) }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canContinue)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 52)
        .frame(height: 84)
    }

    private var nextLabel: String {
        switch step {
        case .welcome: "Get started"
        case .done: "Start using Usami"
        default: "Continue"
        }
    }

    private func go(_ delta: Int) {
        guard let next = SetupStep(rawValue: step.rawValue + delta) else { return }
        if next == .access { trusted = AXText.isTrusted() }
        withAnimation(.easeOut(duration: 0.3)) { step = next }
    }
}

// MARK: - Pieces shared with the home window

/// Large selectable provider card.
struct ProviderCard: View {
    var kind: ProviderKind
    var selected: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    ProviderMark(provider: kind, size: 28)
                        .frame(width: 50, height: 50)
                        .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(Theme.chip))
                    Spacer()
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(AppPalette.button))
                        .scaleEffect(selected ? 1 : 0.4)
                        .opacity(selected ? 1 : 0)
                }
                Text(kind.displayName)
                    .font(.system(size: 18, weight: .semibold))
                    .padding(.top, 18)
                Text(kind.planBlurb)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(22)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: AppPalette.blue.opacity(selected ? 0.14 : 0), radius: 16, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(selected ? Theme.accent : Theme.line, lineWidth: selected ? 1.5 : 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.soft)
                    .padding(selected ? -4 : 0)
                    .opacity(selected ? 1 : 0)
            )
            .offset(y: hovering ? -2 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Capsule picker for the provider's models.
struct ModelPills: View {
    var provider: ProviderKind
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        HStack(spacing: 9) {
            ForEach(provider.models, id: \.self) { model in
                let on = settings.currentModel == model
                Button { settings.currentModel = model } label: {
                    Text(model)
                        .font(.system(size: 13, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? Theme.accent : Theme.muted)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(on ? Theme.soft : Theme.card)
                                .overlay(Capsule().strokeBorder(on ? Theme.accent : Theme.line, lineWidth: 1))
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.15), value: settings.currentModel)
    }
}

/// Real sign-in flow for either provider, in a card.
struct ProviderSignInPanel: View {
    var provider: ProviderKind
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var claude = ClaudeAuth.shared
    @ObservedObject private var codex = CodexAuth.shared
    @State private var pastedCode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                ProviderMark(provider: provider, size: 30)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 17, style: .continuous).fill(Theme.chip))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text(provider.displayName).font(.system(size: 16, weight: .semibold))
                        Text("· \(settings.currentModel)").font(.system(size: 16)).foregroundStyle(Theme.muted)
                    }
                    status
                }
                Spacer()
                trailingButton
            }
            detail
            if let error = provider == .claude ? claude.lastError : codex.lastError {
                Text(error).font(.system(size: 12.5)).foregroundStyle(.red)
            }
        }
        .card(radius: 18, padding: 22)
    }

    private var signedIn: Bool { provider == .claude ? claude.isSignedIn : codex.isSignedIn }

    @ViewBuilder
    private var status: some View {
        if signedIn {
            StatusChip(text: "Connected", icon: "checkmark")
        } else if provider == .claude && claude.awaitingCode {
            Text("Approve in your browser, then paste the code").font(.system(size: 13)).foregroundStyle(Theme.muted)
        } else if provider == .codex, case .waiting = codex.phase {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval in your browser…").font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        } else {
            Text("Not connected yet").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if signedIn {
            Button("Sign out") { provider == .claude ? claude.signOut() : codex.signOut() }
                .buttonStyle(SoftButtonStyle(compact: true))
        } else if provider == .claude && !claude.awaitingCode {
            Button("Sign in") { claude.beginSignIn() }.buttonStyle(PrimaryButtonStyle())
        } else if provider == .codex, codex.phase == .idle {
            Button("Sign in") { codex.beginSignIn() }.buttonStyle(PrimaryButtonStyle())
        } else {
            Button("Cancel") { provider == .claude ? claude.cancelSignIn() : codex.cancelSignIn() }
                .buttonStyle(SoftButtonStyle(compact: true))
        }
    }

    @ViewBuilder
    private var detail: some View {
        if provider == .claude && claude.awaitingCode && !claude.isSignedIn {
            HStack(spacing: 10) {
                TextField("Paste code here", text: $pastedCode)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chip))
                Button("Connect") {
                    Task { await claude.completeSignIn(pasted: pastedCode); pastedCode = "" }
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
                .disabled(pastedCode.trimmingCharacters(in: .whitespaces).isEmpty || claude.isWorking)
            }
        } else if provider == .codex, case .waiting(let code, let url) = codex.phase {
            HStack(spacing: 12) {
                Text(code)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                }
                .buttonStyle(SoftButtonStyle(compact: true))
                Button("Open page") { if let link = URL(string: url) { NSWorkspace.shared.open(link) } }
                    .buttonStyle(SoftButtonStyle(compact: true))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chip))
        }
    }
}

/// The app badge with two soft rings radiating out of it.
struct PulsingBadge: View {
    var size: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .strokeBorder(AppPalette.skyBlue, lineWidth: 2)
                    .scaleEffect(pulse ? 1.7 : 1)
                    .opacity(pulse ? 0 : 0.55)
                    .animation(.easeOut(duration: 2.4).repeatForever(autoreverses: false).delay(Double(i) * 1.2), value: pulse)
            }
            SparkleBadge(size: size)
        }
        .frame(width: size, height: size)
        .onAppear { pulse = true }
    }
}

/// A looping preview of the trigger and the card filling in.
private struct SelectionDemo: View {
    var provider: ProviderKind
    var model: String
    @State private var showResult = false
    private let loop = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                SparkleBadge(size: 24)
                HStack(spacing: 0) {
                    Text("Hey team, ")
                    Text("let's use the nativ swift and make this app")
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(AppPalette.skyBlue.opacity(0.3)))
                }
                .font(.system(size: 16))
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text("Improve").font(.system(size: 12.5, weight: .semibold))
                    Text("\(provider.shortName) · \(model)").font(.system(size: 11.5)).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 16).padding(.top, 12)
                ZStack(alignment: .topLeading) {
                    if showResult {
                        Text("Let's use native Swift and build an app that works across my whole application.")
                            .font(.system(size: 13.5))
                            .lineSpacing(3)
                            .transition(.opacity.combined(with: .offset(y: 4)))
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ShimmerBar(width: 300)
                            ShimmerBar(width: 190)
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
                .frame(height: 46, alignment: .topLeading)
                .padding(.horizontal, 16).padding(.top, 8)
                HStack(spacing: 6) {
                    Text("Accept").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppPalette.button))
                    Text("Copy").font(.system(size: 12)).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.chip))
                }
                .padding(16)
            }
            .frame(width: 370)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.card)
                    .shadow(color: .black.opacity(0.12), radius: 20, y: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
            .padding(.leading, 26)
        }
        .onReceive(loop) { _ in withAnimation(.easeInOut(duration: 0.4)) { showResult.toggle() } }
    }
}

/// A placeholder line with a highlight sweeping across it.
struct ShimmerBar: View {
    var width: CGFloat
    var height: CGFloat = 9

    var body: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
            Capsule()
                .fill(Theme.chip)
                .overlay {
                    LinearGradient(colors: [.clear, Theme.soft, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width * 0.6)
                        .offset(x: -width * 0.6 + phase * width * 1.6)
                }
                .clipShape(Capsule())
        }
        .frame(width: width, height: height)
    }
}
