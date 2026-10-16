import AppKit
import SwiftUI

// Shared look for every Usami window: the blue sparkle brand, light/dark tokens and controls.

// MARK: - Brand

/// Four-point sparkle with concave sides, the same shape as the app icon's stars.
struct Sparkle: Shape {
    var pinch: CGFloat = 0.10

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let k = r * pinch
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
        p.closeSubpath()
        return p
    }
}

enum AppPalette {
    static let skyBlue = Color(red: 0.35, green: 0.72, blue: 1.00)
    static let blue = Color(red: 0.15, green: 0.47, blue: 1.00)
    static let deepBlue = Color(red: 0.08, green: 0.28, blue: 0.88)

    static let gradient = LinearGradient(
        colors: [skyBlue, blue, deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Fill for primary buttons and "done" marks.
    static let button = LinearGradient(
        colors: [Color(red: 0.23, green: 0.48, blue: 0.96), Color(red: 0.12, green: 0.33, blue: 0.85)],
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    /// A color that follows the window's light/dark appearance.
    static func adaptive(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

enum Theme {
    static let window = Color.adaptive(light: rgb(251, 252, 254), dark: rgb(20, 23, 31))
    static let card = Color.adaptive(light: .white, dark: rgb(27, 32, 43))
    static let line = Color.adaptive(light: rgb(15, 23, 42, 0.09), dark: rgb(255, 255, 255, 0.09))
    static let text = Color.adaptive(light: rgb(15, 23, 42), dark: rgb(238, 241, 247))
    static let muted = Color.adaptive(light: rgb(86, 97, 118), dark: rgb(163, 173, 191))
    static let faint = Color.adaptive(light: rgb(122, 134, 153), dark: rgb(124, 135, 155))
    static let accent = Color.adaptive(light: rgb(37, 99, 235), dark: rgb(106, 160, 255))
    static let soft = Color.adaptive(light: rgb(37, 99, 235, 0.09), dark: rgb(106, 160, 255, 0.16))
    static let chip = Color.adaptive(light: rgb(15, 23, 42, 0.05), dark: rgb(255, 255, 255, 0.07))
    static let ok = Color.adaptive(light: rgb(21, 128, 61), dark: rgb(74, 222, 128))
    static let okSoft = Color.adaptive(light: rgb(21, 128, 61, 0.11), dark: rgb(74, 222, 128, 0.13))
    static let warn = Color.adaptive(light: rgb(180, 83, 9), dark: rgb(251, 191, 36))
    static let warnSoft = Color.adaptive(light: rgb(180, 83, 9, 0.10), dark: rgb(251, 191, 36, 0.13))
    static let claude = Color(red: 0.85, green: 0.47, blue: 0.34)
    static let switchOn = Color(red: 0.20, green: 0.78, blue: 0.35)
}

/// The app icon in miniature: blue gradient disc with the white sparkles.
struct SparkleBadge: View {
    var size: CGFloat = 34
    var glow = true

    var body: some View {
        ZStack {
            Circle().fill(AppPalette.gradient)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 0.75)
            SparkleGlyph(color: .white)
                .frame(width: size * 0.6, height: size * 0.6)
        }
        .frame(width: size, height: size)
        .shadow(color: glow ? AppPalette.blue.opacity(0.4) : .clear, radius: size * 0.22, y: size * 0.1)
    }
}

/// One large and one small sparkle, laid out like the app icon.
struct SparkleGlyph: View {
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Sparkle().fill(color)
                    .frame(width: s * 0.78, height: s * 0.78)
                    .position(x: s * 0.44, y: s * 0.56)
                Sparkle().fill(color)
                    .frame(width: s * 0.3, height: s * 0.3)
                    .position(x: s * 0.84, y: s * 0.18)
            }
        }
    }
}

// MARK: - Provider marks

/// Simple drawn marks for the two providers (stand-ins, not the official logos).
struct ProviderMark: View {
    var provider: ProviderKind
    var size: CGFloat = 24

    var body: some View {
        switch provider {
        case .claude:
            ClaudeBurst()
                .stroke(Theme.claude, style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                .frame(width: size, height: size)
        case .codex:
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    RoundedRectangle(cornerRadius: size * 0.17)
                        .stroke(Theme.text, lineWidth: size * 0.07)
                        .frame(width: size * 0.34, height: size * 0.8)
                        .rotationEffect(.degrees(Double(i) * 60))
                }
            }
            .frame(width: size, height: size)
        }
    }
}

private struct ClaudeBurst: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        var p = Path()
        for i in 0..<8 {
            // Explicit Double math converted to CGFloat: older toolchains find a bare cos() ambiguous here.
            let angle = Double(i) * Double.pi / 4
            let dx = CGFloat(Foundation.cos(angle))
            let dy = CGFloat(Foundation.sin(angle))
            let inner = r * 0.3
            let outer = r * (i.isMultiple(of: 2) ? 0.95 : 0.8)
            p.move(to: CGPoint(x: c.x + dx * inner, y: c.y + dy * inner))
            p.addLine(to: CGPoint(x: c.x + dx * outer, y: c.y + dy * outer))
        }
        return p
    }
}

extension ProviderKind {
    var displayName: String { self == .claude ? "Claude" : "ChatGPT Codex" }
    var shortName: String { self == .claude ? "Claude" : "Codex" }
    var models: [String] { self == .claude ? Settings.claudeModels : Settings.codexModels }
    var planBlurb: String {
        self == .claude
            ? "Uses your Claude Pro or Max plan through the Claude Code sign-in."
            : "Uses your ChatGPT Plus or Pro plan through the Codex sign-in."
    }
}

extension Settings {
    var currentModel: String {
        get { provider == .claude ? claudeModel : codexModel }
        set { if provider == .claude { claudeModel = newValue } else { codexModel = newValue } }
    }
}

// MARK: - Controls

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, compact: compact)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12.5 : 13.5, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, compact ? 13 : 20)
                .padding(.vertical, compact ? 7 : 11)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                        .fill(AppPalette.button)
                        .overlay(
                            RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                        )
                )
                .shadow(color: AppPalette.blue.opacity(isEnabled ? (hovering ? 0.45 : 0.32) : 0), radius: hovering ? 10 : 7, y: 4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .offset(y: hovering && !configuration.isPressed ? -1 : 0)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

struct SoftButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, compact: compact)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: compact ? 12.5 : 13.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.horizontal, compact ? 12 : 18)
                .padding(.vertical, compact ? 7 : 11)
                .background(
                    RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                        .fill(hovering ? Theme.soft : Theme.chip)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}

/// iOS-style green switch, drawn so it looks the same in every window.
struct PillSwitch: View {
    @Binding var isOn: Bool
    var width: CGFloat = 44
    var label: String

    var body: some View {
        let height = width * 0.59
        let knob = height - 6
        Button { isOn.toggle() } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.switchOn : Theme.line)
                Circle().fill(.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(3)
            }
            .frame(width: width, height: height)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isOn)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// Small colored capsule such as "Connected" or "On".
struct StatusChip: View {
    enum Tone { case ok, warn, neutral, accent }
    var text: String
    var icon: String?
    var tone: Tone = .ok

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5, weight: .bold)) }
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch tone {
        case .ok: Theme.ok
        case .warn: Theme.warn
        case .neutral: Theme.muted
        case .accent: Theme.accent
        }
    }

    private var background: Color {
        switch tone {
        case .ok: Theme.okSoft
        case .warn: Theme.warnSoft
        case .neutral: Theme.chip
        case .accent: Theme.soft
        }
    }
}

/// White (or dark) rounded card with a hairline border.
struct CardBackground: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.line, lineWidth: 1)
            )
    }
}

extension View {
    func card(radius: CGFloat = 18, padding: CGFloat = 18) -> some View {
        modifier(CardBackground(radius: radius, padding: padding))
    }
}

/// Rounded icon tile used beside headings.
struct IconTile: View {
    var systemName: String
    var tint: Color = Theme.accent
    var fill: Color = Theme.soft
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.32, style: .continuous).fill(fill))
    }
}

/// Native translucent sidebar material.
struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - Windows

/// A window with a transparent title bar so content runs up to the traffic lights.
@MainActor
func makeAppWindow<Content: View>(size: NSSize, title: String, content: Content) -> NSWindow {
    let window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    window.title = title
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    window.isMovableByWindowBackground = true
    window.isReleasedWhenClosed = false
    window.backgroundColor = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 20 / 255, green: 23 / 255, blue: 31 / 255, alpha: 1)
            : NSColor(srgbRed: 251 / 255, green: 252 / 255, blue: 254 / 255, alpha: 1)
    }
    // The hosting view would otherwise grow the window by the title bar's height.
    let host = NSHostingView(rootView: content)
    host.sizingOptions = []
    window.contentView = host
    window.setFrame(NSRect(origin: window.frame.origin, size: size), display: false)
    window.center()
    return window
}
