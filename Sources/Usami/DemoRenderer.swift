import AppKit
import ApplicationServices
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Renders the README demo GIF from the app's real views (no screen recording involved):
//   Usami --render-demo docs/images
// It animates a scripted session — select text, open the card, Improve, Rephrase, Translate,
// More ▸ Make shorter, Accept — with a cursor, and writes demo.gif.

// MARK: - Scene description

private enum Geo {
    static let size = CGSize(width: 640, height: 400)

    // Text
    static let textLeft: CGFloat = 78
    static let line1Y: CGFloat = 118          // vertical centre of the first text line
    static let lineHeight: CGFloat = 28
    static let font = NSFont.systemFont(ofSize: 17)

    // Card (the view origin includes its 8pt outer padding)
    static let cardOrigin = CGPoint(x: 58, y: 168)
    // Positions inside the card, relative to the card view origin (tuned from test renders).
    static let tabY: CGFloat = 175
    static let improveX: CGFloat = 50
    static let rephraseX: CGFloat = 125
    static let translateX: CGFloat = 202
    static let moreX: CGFloat = 266
    static let acceptX: CGFloat = 55
    static let buttonsY: CGFloat = 104
    static let closeX: CGFloat = 369
}

private struct DemoCardState {
    var action: RewriteAction
    var result: String
    var loading: Bool
}

private struct DemoMenu {
    var anchorX: CGFloat            // left edge of the menu
    var bottomY: CGFloat            // bottom edge (menus open upward here, like near a screen edge)
    var items: [String]
    var hovered: Int?
}

private struct DemoState {
    var cursor = CGPoint(x: 560, y: 350)
    var cursorVisible = true
    var click = 0.0                 // 0 = idle, 0…1 = click ripple progress
    var selection = 0.0             // fraction of the sentence selected
    var triggerOpacity = 0.0
    var card: DemoCardState?
    var menu: DemoMenu?
    var finalLines: [String]?       // replaces the sentence after Accept
    var spinner = 0.0
}

private let originalLines = [
    "hey team, i think we shoud move the meeting to thrusday",
    "becuase alot of people is out",
]

// MARK: - Views

private struct DemoScene: View {
    let state: DemoState
    let model: PopupModel
    /// Plain white backdrop (for social posts) instead of the soft gradient desktop.
    var whiteBackground = false

    private func width(_ text: String) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: Geo.font]).width
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Desktop backdrop
            if whiteBackground {
                Color.white
            } else {
                LinearGradient(
                    colors: [Color(red: 0.86, green: 0.89, blue: 0.97), Color(red: 0.93, green: 0.88, blue: 0.96)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }

            // App window
            VStack(spacing: 0) {
                ZStack {
                    Color(white: 0.965)
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
                        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
                        Spacer()
                    }
                    .padding(.leading, 14)
                    Text("Weekly sync — Notes")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Color(white: 0.42))
                }
                .frame(height: 38)
                Divider()
                Color.white
            }
            .frame(width: 600, height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color.black.opacity(whiteBackground ? 0.14 : 0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(whiteBackground ? 0.10 : 0.18), radius: whiteBackground ? 10 : 14, y: 5)
            .offset(x: 20, y: 20)

            // Text with the progressive selection
            textBlock

            // Trigger (left of the selection)
            if state.triggerOpacity > 0 && state.card == nil {
                PopupPreviewParts.trigger(model)
                    .opacity(state.triggerOpacity)
                    .offset(x: Geo.textLeft - 40, y: Geo.line1Y - 16)
            }

            // Card
            if state.card != nil {
                PopupPreviewParts.card(model)
                    .fixedSize()
                    .offset(x: Geo.cardOrigin.x, y: Geo.cardOrigin.y)
            }

            // Dropdown menu
            if let menu = state.menu {
                menuView(menu)
            }

            // Cursor
            if state.cursorVisible {
                CursorView(click: state.click)
                    .offset(x: state.cursor.x, y: state.cursor.y)
            }
        }
        .frame(width: Geo.size.width, height: Geo.size.height, alignment: .topLeading)
        .clipped()
    }

    private var textBlock: some View {
        let lines = state.finalLines ?? originalLines
        let total = originalLines.reduce(0) { $0 + $1.count }
        let selected = state.finalLines == nil ? Int((state.selection * Double(total)).rounded()) : 0

        return ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                let count = min(remainingSelected(for: index, selected: selected), line.count)
                let prefix = String(line.prefix(count))
                ZStack(alignment: .leading) {
                    if count > 0 {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.30))
                            .frame(width: width(prefix), height: 24)
                    }
                    Text(line)
                        .font(.system(size: 17))
                        .foregroundStyle(Color(white: 0.12))
                        .fixedSize()
                }
                .offset(x: Geo.textLeft, y: Geo.line1Y - 12 + CGFloat(index) * Geo.lineHeight)
            }
        }
    }

    private func remainingSelected(for index: Int, selected: Int) -> Int {
        var left = selected
        for i in 0..<index { left -= originalLines[i].count }
        return max(0, left)
    }

    private func menuView(_ menu: DemoMenu) -> some View {
        let rowHeight: CGFloat = 25
        let height = CGFloat(menu.items.count) * rowHeight + 10
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(menu.items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(.system(size: 13))
                    .foregroundStyle(menu.hovered == index ? Color.white : Color(white: 0.1))
                    .padding(.horizontal, 10)
                    .frame(width: 168, height: rowHeight, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(menu.hovered == index ? Color.accentColor : .clear)
                    )
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        .offset(x: menu.anchorX, y: menu.bottomY - height)
    }
}

private struct CursorView: View {
    let click: Double

    var body: some View {
        ZStack(alignment: .topLeading) {
            if click > 0 {
                Circle()
                    .strokeBorder(Color.black.opacity(0.35 * (1 - click)), lineWidth: 2)
                    .frame(width: 10 + 30 * click, height: 10 + 30 * click)
                    .offset(x: -(5 + 15 * click), y: -(5 + 15 * click))
            }
            Path { p in
                p.move(to: CGPoint(x: 0, y: 0))
                p.addLine(to: CGPoint(x: 0, y: 17))
                p.addLine(to: CGPoint(x: 4.3, y: 13.2))
                p.addLine(to: CGPoint(x: 7.2, y: 19.6))
                p.addLine(to: CGPoint(x: 10, y: 18.4))
                p.addLine(to: CGPoint(x: 7.2, y: 12.2))
                p.addLine(to: CGPoint(x: 12.4, y: 12.2))
                p.closeSubpath()
            }
            .fill(Color.black)
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0))
                    p.addLine(to: CGPoint(x: 0, y: 17))
                    p.addLine(to: CGPoint(x: 4.3, y: 13.2))
                    p.addLine(to: CGPoint(x: 7.2, y: 19.6))
                    p.addLine(to: CGPoint(x: 10, y: 18.4))
                    p.addLine(to: CGPoint(x: 7.2, y: 12.2))
                    p.addLine(to: CGPoint(x: 12.4, y: 12.2))
                    p.closeSubpath()
                }
                .stroke(Color.white, lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
        }
        .frame(width: 1, height: 1, alignment: .topLeading)
    }
}

// MARK: - Timeline

@MainActor
private final class DemoBuilder {
    private let model = PopupModel()
    private let info: SelectionInfo
    private(set) var frames: [(image: CGImage, delay: Double)] = []
    private var lastKey: String?
    var debugDirectory: String?
    var whiteBackground = false
    /// When set, the frame with this tag is also written as a PNG still to `stillURL`.
    var stillTag: String?
    var stillURL: URL?
    private var debugCount = 0

    init() {
        info = SelectionInfo(
            text: originalLines.joined(separator: " "),
            element: AXUIElementCreateSystemWide(),
            rect: .zero, firstLineRect: nil, isEditable: true, app: nil
        )
    }

    // Rendering ---------------------------------------------------------------------------

    private func render(_ state: DemoState) -> CGImage? {
        PopupPreviewParts.spinnerAngle = state.spinner
        if let card = state.card {
            model.configureForPreview(
                selection: info, result: card.loading ? "" : card.result,
                action: card.action, isLoading: card.loading
            )
        }
        let renderer = ImageRenderer(
            content: DemoScene(state: state, model: model, whiteBackground: whiteBackground)
                .environment(\.colorScheme, .light)
        )
        renderer.scale = 1.5
        return renderer.cgImage
    }

    /// Adds a frame shown for `seconds`. Identical consecutive frames are merged.
    func frame(_ state: DemoState, seconds: Double, tag: String? = nil) {
        guard let image = render(state) else { return }
        if let tag, tag == stillTag, let stillURL {
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: stillURL)
        }
        if let debugDirectory, let tag {
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: debugDirectory).appendingPathComponent("\(String(format: "%02d", debugCount))-\(tag).png"))
                debugCount += 1
            }
        }
        frames.append((image, seconds))
    }

    private func ease(_ t: Double) -> Double { t * t * (3 - 2 * t) }

    /// Moves the cursor over `seconds` (≈13 fps), letting the caller adjust the state per step.
    func move(_ state: DemoState, to target: CGPoint, seconds: Double, step: ((inout DemoState, Double) -> Void)? = nil) -> DemoState {
        let count = max(2, Int(seconds * 13))
        var s = state
        let from = state.cursor
        for i in 1...count {
            let t = ease(Double(i) / Double(count))
            s.cursor = CGPoint(x: from.x + (target.x - from.x) * t, y: from.y + (target.y - from.y) * t)
            step?(&s, t)
            frame(s, seconds: 1.0 / 13.0)
        }
        return s
    }

    func click(_ state: DemoState) -> DemoState {
        var s = state
        for p in [0.15, 0.5, 0.85] {
            s.click = p
            frame(s, seconds: 0.06)
        }
        s.click = 0
        return s
    }

    func spin(_ state: DemoState, seconds: Double, tag: String? = nil) {
        var s = state
        let count = max(2, Int(seconds * 9))
        for i in 0..<count {
            s.spinner = Double(i) * 50
            frame(s, seconds: 1.0 / 9.0, tag: i == 1 ? tag : nil)
        }
    }

    // Script ------------------------------------------------------------------------------

    func build() {
        func textWidth(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: Geo.font]).width }
        let len1 = originalLines[0].count
        let total = originalLines.reduce(0) { $0 + $1.count }
        let cardX = Geo.cardOrigin.x, cardY = Geo.cardOrigin.y

        func tab(_ x: CGFloat) -> CGPoint { CGPoint(x: cardX + x, y: cardY + Geo.tabY) }

        var s = DemoState()
        frame(s, seconds: 0.9, tag: "start")

        // 1. Move to the start of the text, then drag-select the sentence.
        s = move(s, to: CGPoint(x: Geo.textLeft - 1, y: Geo.line1Y + 4), seconds: 0.8)
        s.click = 0
        let n = 16
        for i in 1...n {
            let t = Double(i) / Double(n)
            s.selection = ease(t)
            let chars = Int((s.selection * Double(total)).rounded())
            if chars <= len1 {
                let prefix = String(originalLines[0].prefix(chars))
                s.cursor = CGPoint(x: Geo.textLeft + textWidth(prefix), y: Geo.line1Y + 4)
            } else {
                let prefix = String(originalLines[1].prefix(chars - len1))
                s.cursor = CGPoint(x: Geo.textLeft + textWidth(prefix), y: Geo.line1Y + 4 + Geo.lineHeight)
            }
            frame(s, seconds: 0.07)
        }
        s.selection = 1
        frame(s, seconds: 0.35, tag: "selected")

        // 2. The trigger fades in to the left of the selection.
        for o in [0.35, 0.7, 1.0] {
            s.triggerOpacity = o
            frame(s, seconds: 0.07)
        }
        frame(s, seconds: 0.5, tag: "trigger")

        // 3. Click the trigger → card opens and runs Improve.
        s = move(s, to: CGPoint(x: Geo.textLeft - 24, y: Geo.line1Y + 2), seconds: 0.7)
        s = click(s)
        s.triggerOpacity = 0
        let improved = "Hey team, I think we should move the meeting to Thursday because a lot of people are out."
        s.card = DemoCardState(action: .improve, result: improved, loading: true)
        s.cursor = CGPoint(x: s.cursor.x + 120, y: s.cursor.y + 100)
        s = move(s, to: CGPoint(x: cardX + 250, y: cardY + 96), seconds: 0.5)
        spin(s, seconds: 0.9, tag: "loading")
        s.card = DemoCardState(action: .improve, result: improved, loading: false)
        frame(s, seconds: 1.9, tag: "improve")

        // 4. Rephrase.
        s = move(s, to: tab(Geo.rephraseX), seconds: 0.6)
        s = click(s)
        s.card = DemoCardState(action: .rephrase, result: "", loading: true)
        spin(s, seconds: 0.8)
        s.card = DemoCardState(
            action: .rephrase,
            result: "Hi everyone — let's shift the meeting to Thursday, since many of us will be away.",
            loading: false
        )
        frame(s, seconds: 2.0, tag: "rephrase")

        // 5. Translate ▸ Spanish.
        s = move(s, to: tab(Geo.translateX), seconds: 0.6)
        s = click(s)
        let languages = ["English", "Spanish", "French", "German", "Urdu", "Arabic"]
        let menuBottom = cardY + Geo.tabY - 20
        s.menu = DemoMenu(anchorX: cardX + Geo.translateX - 40, bottomY: menuBottom, items: languages, hovered: nil)
        frame(s, seconds: 0.5, tag: "translate-menu")
        let spanishY = menuBottom - CGFloat(languages.count) * 25 - 10 + 5 + 25 * 1 + 12
        s = move(s, to: CGPoint(x: cardX + Geo.translateX + 6, y: spanishY), seconds: 0.5) { st, _ in
            st.menu?.hovered = nil
        }
        s.menu?.hovered = 1
        frame(s, seconds: 0.4, tag: "translate-hover")
        s = click(s)
        s.menu = nil
        s.card = DemoCardState(action: .translate("Spanish"), result: "", loading: true)
        spin(s, seconds: 0.8)
        s.card = DemoCardState(
            action: .translate("Spanish"),
            result: "Hola equipo, creo que deberíamos mover la reunión al jueves porque mucha gente no está.",
            loading: false
        )
        frame(s, seconds: 2.2, tag: "translate")

        // 6. More ▸ Make shorter.
        s = move(s, to: tab(Geo.moreX), seconds: 0.6)
        s = click(s)
        let more = ["Fix grammar", "Make shorter", "Make longer", "More formal", "More casual", "Summarize"]
        s.menu = DemoMenu(anchorX: cardX + Geo.moreX - 40, bottomY: menuBottom, items: more, hovered: nil)
        frame(s, seconds: 0.5, tag: "more-menu")
        let shorterY = menuBottom - CGFloat(more.count) * 25 - 10 + 5 + 25 * 1 + 12
        s = move(s, to: CGPoint(x: cardX + Geo.moreX + 6, y: shorterY), seconds: 0.5)
        s.menu?.hovered = 1
        frame(s, seconds: 0.4)
        s = click(s)
        s.menu = nil
        let shorter = "Let's move the meeting to Thursday — many people are out."
        s.card = DemoCardState(action: .shorter, result: "", loading: true)
        spin(s, seconds: 0.7)
        s.card = DemoCardState(action: .shorter, result: shorter, loading: false)
        frame(s, seconds: 2.0, tag: "shorter")

        // 7. Accept → the text is replaced and the card closes.
        s = move(s, to: CGPoint(x: cardX + Geo.acceptX, y: cardY + Geo.buttonsY), seconds: 0.7)
        s = click(s)
        s.card = nil
        s.selection = 0
        s.finalLines = [shorter, ""]
        s.triggerOpacity = 0
        frame(s, seconds: 0.3)
        s = move(s, to: CGPoint(x: 520, y: 320), seconds: 0.8)
        frame(s, seconds: 2.4, tag: "done")
    }
}

// MARK: - GIF writer

@MainActor
func renderDemo(to directory: String, debug: Bool, whiteBackground: Bool = false) {
    _ = NSApplication.shared
    let appearance = NSAppearance(named: .aqua)
    NSApp.appearance = appearance
    NSAppearance.current = appearance
    // Keep the card the same size in loading and result states so cursor targets stay put.
    PopupPreviewParts.contentMinHeight = 100

    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let builder = DemoBuilder()
    builder.whiteBackground = whiteBackground
    if debug { builder.debugDirectory = directory }
    let name = whiteBackground ? "demo-white" : "demo"
    if whiteBackground {
        builder.stillTag = "improve"
        builder.stillURL = URL(fileURLWithPath: directory).appendingPathComponent("usage-white.png")
    }
    builder.build()

    guard let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: directory).appendingPathComponent("\(name).gif") as CFURL,
        UTType.gif.identifier as CFString, builder.frames.count, nil
    ) else {
        print("could not create demo.gif")
        return
    }
    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
    ] as CFDictionary)
    for frame in builder.frames {
        CGImageDestinationAddImage(destination, frame.image, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: frame.delay],
        ] as CFDictionary)
    }
    if CGImageDestinationFinalize(destination) {
        let total = builder.frames.reduce(0) { $0 + $1.delay }
        print("wrote \(name).gif — \(builder.frames.count) frames, \(String(format: "%.1f", total))s")
    } else {
        print("failed to write demo.gif")
    }
}
