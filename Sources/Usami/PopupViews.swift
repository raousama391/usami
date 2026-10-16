import SwiftUI

struct PopupRootView: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        switch model.phase {
        case .trigger: TriggerButton(model: model)
        case .card: SuggestionCard(model: model)
        }
    }
}

/// Internal entry points to the file-private views, used only by PreviewRenderer.
enum PopupPreviewParts {
    /// Rotation of the static spinner, set per frame by the demo renderer.
    @MainActor static var spinnerAngle = 0.0
    /// Minimum height of the card's content area in offscreen renders (0 = natural height).
    @MainActor static var contentMinHeight: CGFloat = 0

    @MainActor static func trigger(_ model: PopupModel) -> some View { TriggerButton(model: model, animated: false) }
    @MainActor static func card(_ model: PopupModel) -> some View { SuggestionCard(model: model, staticPreview: true) }
}

// MARK: - Trigger (the app's sparkle in a round badge, left of the selection)

enum PopupMetrics {
    /// Room around the 24pt badge so its pulse and glow never reach the panel's square edges.
    static let triggerSize = NSSize(width: 48, height: 48)
}

private struct TriggerButton: View {
    @ObservedObject var model: PopupModel
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var entered: Bool
    @State private var starPop: [Double]
    @State private var spin = 0.0
    @State private var twinkle = 0.0
    @State private var ripple = 0.0
    @State private var glow = 0.0

    /// False for offscreen renders, which draw the settled state only.
    private let animated: Bool

    init(model: PopupModel, animated: Bool = true) {
        self.model = model
        self.animated = animated
        _entered = State(initialValue: !animated)
        _starPop = State(initialValue: animated ? [0, 0, 0] : [1, 1, 1])
    }

    private var isOutline: Bool { settings.triggerStyle == .outline }

    /// App-icon look (blue gradient badge, white stars) or, for "outline", a plain badge with blue stars.
    private var disc: AnyShapeStyle {
        if isOutline { return AnyShapeStyle(scheme == .dark ? Color(white: 0.13) : Color.white) }
        return AnyShapeStyle(AppPalette.gradient)
    }

    private var ring: Color { isOutline ? AppPalette.blue : .white.opacity(0.35) }

    private var starStyle: AnyShapeStyle {
        isOutline ? AnyShapeStyle(AppPalette.gradient) : AnyShapeStyle(Color.white)
    }

    var body: some View {
        Button(action: model.expand) {
            ZStack {
                // Round ripple that radiates out of the badge now and then.
                Circle()
                    .strokeBorder(AppPalette.blue.opacity((1 - ripple) * 0.6), lineWidth: 1.5)
                    .scaleEffect(1 + ripple * 0.3)
                    .opacity(ripple > 0 ? 1 : 0)

                Circle().fill(disc)
                Circle().strokeBorder(ring, lineWidth: isOutline ? 1.5 : 0.75)

                ZStack {
                    Sparkle()
                        .fill(starStyle)
                        .frame(width: 13.5, height: 13.5)
                        .rotationEffect(.degrees(spin + (hovering ? 90 : 0)))
                        .scaleEffect(starPop[0])
                        .offset(x: -1.1, y: 1.0)
                    Sparkle()
                        .fill(starStyle)
                        .frame(width: 5.4, height: 5.4)
                        .rotationEffect(.degrees(starPop[1] == 1 ? twinkle * 90 : -180))
                        .scaleEffect(starPop[1] * (1 + twinkle * 0.45))
                        .offset(x: 5.2, y: -5.2)
                    Sparkle()
                        .fill(starStyle)
                        .frame(width: 2.8, height: 2.8)
                        .rotationEffect(.degrees(starPop[2] == 1 ? -twinkle * 90 : 180))
                        .scaleEffect(starPop[2] * (1 + twinkle * 0.6))
                        .offset(x: 5.0, y: 5.0)
                }
                .opacity(entered ? 1 : 0)
            }
            .frame(width: 24, height: 24)
            .shadow(color: AppPalette.blue.opacity(glow * 0.6), radius: 2 + glow * 3)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .scaleEffect(entered ? (hovering ? 1.1 : 1) : 0.2)
            .opacity(entered ? 1 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: PopupMetrics.triggerSize.width, height: PopupMetrics.triggerSize.height)
        .contentShape(Circle().inset(by: 9))
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: hovering)
        .task(id: model.triggerEpoch) { await playAttention() }
        .help("Improve selected text")
    }

    /// Pops the badge in as a circle, swirls the stars into place, then keeps it twinkling and
    /// rippling for ~12s so it's hard to miss. It settles afterwards so an ignored badge doesn't
    /// animate forever.
    @MainActor
    private func playAttention() async {
        guard animated else { return }
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            entered = false; starPop = [0, 0, 0]; spin = 0; twinkle = 0; ripple = 0; glow = 0
        }

        try? await Task.sleep(for: .milliseconds(30))
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) { entered = true }
        for i in 0..<3 {
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) { starPop[i] = 1 }
        }

        var delay = 250
        for _ in 0..<9 {
            try? await Task.sleep(for: .milliseconds(delay))
            if Task.isCancelled { return }
            delay = 1000

            withAnimation(.easeOut(duration: 1.1)) { ripple = 1 }
            withAnimation(.easeInOut(duration: 0.5)) { glow = 1; twinkle = 1 }
            withAnimation(.easeInOut(duration: 0.8)) { spin += 90 }
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(.easeInOut(duration: 0.5)) { glow = 0; twinkle = 0 }
            try? await Task.sleep(for: .milliseconds(300))
            withTransaction(reset) { ripple = 0 }
        }
    }
}

// MARK: - Card

/// Transparent view that turns a mouse-down into a native window drag. It works on the
/// non-activating panel without making it key, so the app underneath keeps focus.
private struct WindowDragHandle: NSViewRepresentable {
    var onBegin: () -> Void
    var onEnd: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onBegin = onBegin
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.onBegin = onBegin
        view.onEnd = onEnd
    }

    final class DragView: NSView {
        var onBegin: (() -> Void)?
        var onEnd: (() -> Void)?

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

        override func mouseDown(with event: NSEvent) {
            onBegin?()
            window?.performDrag(with: event)   // returns when the mouse is released
            onEnd?()
        }
    }
}

/// A plain drawn spinner used in offscreen renders, where AppKit-backed controls can't be drawn.
private struct StaticSpinner: View {
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.72)
            .stroke(Color.secondary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 12, height: 12)
            .rotationEffect(.degrees(PopupPreviewParts.spinnerAngle))
    }
}

private struct SolidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.88))
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

private struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(.system(size: 12.5))
                .foregroundStyle(Color.primary.opacity(0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06))
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Frosted blur of whatever is behind the card. A raw NSVisualEffectView is used (rather than a
/// SwiftUI Material) so the blur stays active while the non-activating panel isn't key.
private struct BackdropBlur: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}

    private static func mask(cornerRadius: CGFloat) -> NSImage {
        let edge = cornerRadius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}

/// Glass card surface: backdrop blur, a faint light-to-clear tint, and a specular rim.
private struct GlassBackground: View {
    /// Offscreen renders can't blur what's behind them, so they get an opaque base instead.
    var solid: Bool
    @Environment(\.colorScheme) private var scheme

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            if solid {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else {
                BackdropBlur(cornerRadius: 12)
            }
            // Frosted layer: enough body that text always reads, while the backdrop still glows through.
            shape.fill(
                LinearGradient(
                    colors: dark
                        ? [Color(red: 0.12, green: 0.13, blue: 0.17).opacity(0.74), Color(red: 0.09, green: 0.10, blue: 0.13).opacity(0.62)]
                        : [.white.opacity(0.74), .white.opacity(0.56)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            // Specular sheen across the top, like light on a pane of glass.
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(dark ? 0.09 : 0.45), location: 0),
                        .init(color: .white.opacity(0), location: 0.45),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(dark ? 0.38 : 0.85), .white.opacity(0.04), .white.opacity(dark ? 0.14 : 0.35)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
            shape.inset(by: -0.5).strokeBorder(Color.black.opacity(dark ? 0.35 : 0.10), lineWidth: 0.5)
        }
    }
}

/// Sweeps a soft highlight across its content, left to right, on a loop.
private struct Shimmer: ViewModifier {
    var staticPreview: Bool
    private let period = 1.5

    func body(content: Content) -> some View {
        if staticPreview {
            sweep(content, phase: (PopupPreviewParts.spinnerAngle / 360).truncatingRemainder(dividingBy: 1))
        } else {
            TimelineView(.animation) { context in
                sweep(content, phase: context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period)
            }
        }
    }

    private func sweep(_ content: Content, phase: Double) -> some View {
        content.overlay {
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.2), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geo.size.width * 0.5)
                .offset(x: -geo.size.width * 0.5 + phase * geo.size.width * 1.5)
            }
            .mask(content)
        }
    }
}

/// Placeholder text lines shown while the first tokens are on their way.
private struct SkeletonLines: View {
    var staticPreview: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            bar(fraction: 1.0)
            bar(fraction: 0.93)
            bar(fraction: 0.58)
        }
        .modifier(Shimmer(staticPreview: staticPreview))
    }

    private func bar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.primary.opacity(0.09))
                .frame(width: geo.size.width * fraction)
        }
        .frame(height: 9)
    }
}

private struct SuggestionCard: View {
    @ObservedObject var model: PopupModel
    @ObservedObject private var settings = Settings.shared
    /// Renders menus as plain labels so the card can be drawn offscreen for screenshots.
    var staticPreview = false
    @FocusState private var customFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            framedContent
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            Divider()
            actionBar
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .background(GlassBackground(solid: staticPreview))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(8)
        .onChange(of: model.isCustomMode) { _, on in
            if on { DispatchQueue.main.async { customFocused = true } }
        }
    }

    /// For offscreen renders the content area has a fixed height so the card doesn't change size
    /// between loading and result states (keeps animated cursor targets stable).
    @ViewBuilder
    private var framedContent: some View {
        if staticPreview {
            content.frame(maxWidth: .infinity, minHeight: PopupPreviewParts.contentMinHeight, alignment: .topLeading)
        } else {
            content
        }
    }

    @ViewBuilder
    private var spinner: some View {
        if staticPreview {
            StaticSpinner()
        } else {
            ProgressView().controlSize(.small)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(model.action.title)
                .font(.system(size: 12, weight: .semibold))
            Text(model.providerLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.close) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .contentShape(Rectangle())
        // Dragging the header moves the whole card anywhere on screen.
        .background {
            if !staticPreview {
                WindowDragHandle(onBegin: { model.onDragBegan?() }, onEnd: { model.onDragEnded?() })
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isCustomMode {
            customContent
        } else if model.isLoading && model.result.isEmpty {
            loadingBlock
        } else if let error = model.error {
            VStack(alignment: .leading, spacing: 10) {
                errorText(error)
                Button("Try again", action: model.retry)
                    .buttonStyle(GhostButtonStyle())
            }
        } else {
            resultBlock
        }
    }

    private var loadingBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.action.progressLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
            SkeletonLines(staticPreview: staticPreview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func errorText(_ error: String) -> some View {
        Text(error)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var resultBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            if staticPreview {
                resultText
            } else {
                ScrollView { resultText }
                    .frame(maxHeight: 200)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                if model.selection?.isEditable == true {
                    Button("Accept", action: model.accept)
                        .buttonStyle(SolidButtonStyle())
                        .disabled(model.isLoading || model.result.isEmpty)
                }
                Button("Copy", action: model.copy)
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.isLoading || model.result.isEmpty)
                Button("Retry", action: model.retry)
                    .buttonStyle(GhostButtonStyle())
                    .disabled(model.isLoading)
                Spacer()
                if model.isLoading { spinner }
            }
        }
    }

    // MARK: Custom

    private var canSend: Bool {
        !model.customInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.isLoading
    }

    @ViewBuilder
    private var customContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            customField
            if model.isLoading && model.result.isEmpty {
                loadingBlock
            } else if let error = model.error {
                errorText(error)
            } else if !model.result.isEmpty {
                resultBlock
            } else {
                suggestions
            }
        }
        .padding(.top, 2)
    }

    private var customField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.line")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Describe the change you want…", text: $model.customInstruction)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($customFocused)
                .onSubmit { model.submitCustom() }
            Button { model.submitCustom() } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(canSend ? AnyShapeStyle(AppPalette.button) : AnyShapeStyle(Color.secondary.opacity(0.35))))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Apply this change")
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(customFocused ? AppPalette.blue.opacity(0.75) : Color.primary.opacity(0.1), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.15), value: customFocused)
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach([0, 2], id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(PopupModel.customSuggestions[start..<start + 2], id: \.self) { suggestion in
                        Button(suggestion) { model.submitCustom(suggestion) }
                            .buttonStyle(GhostButtonStyle())
                    }
                }
            }
            Text("Only edits the selected text, and gives you one final version.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }

    private var resultText: some View {
        Text(model.result)
            .font(.system(size: 13.5))
            .lineSpacing(3)
            .foregroundStyle(.primary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionBar: some View {
        HStack(spacing: 2) {
            tab(.improve)
            tab(.rephrase)

            if staticPreview {
                tabLabel("Translate", active: isTranslate)
                tabLabel("More", active: isMore)
                tabLabel("Custom", icon: "pencil.line", active: model.isCustomMode)
            } else {
                Menu {
                    ForEach(Settings.languages, id: \.self) { language in
                        Button(language) {
                            settings.translateTo = language
                            model.run(.translate(language))
                        }
                    }
                } label: {
                    tabLabel("Translate", active: isTranslate)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Menu {
                    Button("Fix grammar") { model.run(.fixGrammar) }
                    Button("Make shorter") { model.run(.shorter) }
                    Button("Make longer") { model.run(.longer) }
                    Button("More formal") { model.run(.formal) }
                    Button("More casual") { model.run(.casual) }
                    Button("Summarize") { model.run(.summarize) }
                } label: {
                    tabLabel("More", active: isMore)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button { model.enterCustom() } label: {
                    tabLabel("Custom", icon: "pencil.line", active: model.isCustomMode)
                }
                .buttonStyle(.plain)
                .help("Describe the change in your own words")
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
    }

    private var isTranslate: Bool {
        if case .translate = model.action, !model.isCustomMode { return true }
        return false
    }

    private var isMore: Bool {
        switch model.action {
        case .fixGrammar, .shorter, .longer, .formal, .casual, .summarize: true
        default: false
        }
    }

    private func tab(_ action: RewriteAction) -> some View {
        Button { model.run(action) } label: {
            tabLabel(action.title, active: model.action == action && !model.isCustomMode)
        }
        .buttonStyle(.plain)
    }

    private func tabLabel(_ title: String, icon: String? = nil, active: Bool) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 10.5, weight: .semibold)) }
            Text(title)
        }
            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
    }
}
