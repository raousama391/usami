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

    @MainActor static func trigger(_ model: PopupModel) -> some View { TriggerButton(model: model) }
    @MainActor static func card(_ model: PopupModel) -> some View { SuggestionCard(model: model, staticPreview: true) }
}

// MARK: - Trigger (chevron in a circle, left of the selection)

enum PopupMetrics {
    static let triggerSize = NSSize(width: 32, height: 32)
}

private struct TriggerButton: View {
    @ObservedObject var model: PopupModel
    @ObservedObject private var settings = Settings.shared
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false

    private let blue = Color(red: 0.16, green: 0.46, blue: 0.98)

    private var isOutline: Bool { settings.triggerStyle == .outline }

    private var fill: Color {
        if isOutline { return scheme == .dark ? Color(white: 0.13) : .white }
        return Color.primary          // black in light mode, white in dark mode
    }

    private var ring: Color { isOutline ? blue : .clear }

    private var glyph: Color {
        if isOutline { return Color.primary }
        return Color(nsColor: .windowBackgroundColor)   // inverse of the fill
    }

    var body: some View {
        Button(action: model.expand) {
            ZStack {
                Circle().fill(fill)
                Circle().strokeBorder(ring, lineWidth: 1.75)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(glyph)
            }
            .frame(width: 24, height: 24)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .scaleEffect(hovering ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .frame(width: PopupMetrics.triggerSize.width, height: PopupMetrics.triggerSize.height)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help("Improve selected text")
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

private struct SuggestionCard: View {
    @ObservedObject var model: PopupModel
    @ObservedObject private var settings = Settings.shared
    /// Renders menus as plain labels so the card can be drawn offscreen for screenshots.
    var staticPreview = false

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
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
        .padding(8)
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
        if model.isLoading && model.result.isEmpty {
            HStack(spacing: 8) {
                spinner
                Text(model.action.progressLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else if let error = model.error {
            VStack(alignment: .leading, spacing: 10) {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again", action: model.retry)
                    .buttonStyle(GhostButtonStyle())
            }
        } else {
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
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var isTranslate: Bool {
        if case .translate = model.action { return true }
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
            tabLabel(action.title, active: model.action == action)
        }
        .buttonStyle(.plain)
    }

    private func tabLabel(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Color.primary.opacity(0.08) : .clear)
            )
            .contentShape(Rectangle())
    }
}
