import AppKit
import ApplicationServices
import SwiftUI

// Renders the real popup views offscreen so the README screenshots always match the app:
//   build/Usami.app/Contents/MacOS/Usami --render-previews docs/images

private struct PreviewScene: View {
    @ObservedObject var model: PopupModel
    @Environment(\.colorScheme) private var scheme

    private var sentence: AttributedString {
        var text = AttributedString("Hey team, let's use the nativ swift and make this app that can work on my whole application")
        if let range = text.range(of: "let's use the nativ swift and make this app that can work on my whole application") {
            text[range].backgroundColor = Color.accentColor.opacity(0.28)
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                PreviewTrigger(model: model)
                Text(sentence)
                    .font(.system(size: 15))
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 6)

            PreviewCard(model: model)
                .padding(.leading, 28)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 28)
        .frame(width: 640, alignment: .leading)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.955))
    }
}

// Thin wrappers: the real views are file-private to PopupViews.swift, so expose them through
// internal entry points defined there.
private struct PreviewTrigger: View {
    @ObservedObject var model: PopupModel
    var body: some View { PopupPreviewParts.trigger(model) }
}

private struct PreviewCard: View {
    @ObservedObject var model: PopupModel
    var body: some View { PopupPreviewParts.card(model) }
}

@MainActor
func renderReadmeImages(to directory: String) {
    _ = NSApplication.shared

    let model = PopupModel()
    let info = SelectionInfo(
        text: "let's use the nativ swift and make this app that can work on my whole application",
        element: AXUIElementCreateSystemWide(),
        rect: .zero,
        firstLineRect: nil,
        isEditable: true,
        app: nil
    )
    model.configureForPreview(
        selection: info,
        result: "Let's use native Swift and build an app that works across my whole application."
    )

    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

    let variants: [(name: String, scheme: ColorScheme, appearance: NSAppearance.Name)] = [
        ("screenshot-light", .light, .aqua),
        ("screenshot-dark", .dark, .darkAqua),
    ]
    for variant in variants {
        let appearance = NSAppearance(named: variant.appearance)
        NSApp.appearance = appearance
        NSAppearance.current = appearance

        let renderer = ImageRenderer(
            content: PreviewScene(model: model).environment(\.colorScheme, variant.scheme)
        )
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("failed to render \(variant.name)")
            continue
        }
        let path = (directory as NSString).appendingPathComponent("\(variant.name).png")
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}
