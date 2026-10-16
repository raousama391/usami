#!/usr/bin/env swift
// Generates the Usami app icon: usage `swift scripts/make_icon.swift <output-dir>`
// Writes <output-dir>/AppIcon.iconset/*.png (run `iconutil -c icns` on it afterwards).
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let nsContext = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = nsContext
    let ctx = nsContext.cgContext
    let s = CGFloat(size)
    let rgb = CGColorSpaceCreateDeviceRGB()

    // Icon body (macOS squircle-ish rounded square with standard margin).
    let inset = s * 0.098
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius = body.width * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    // Drop shadow.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.014), blur: s * 0.035,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.38))
    ctx.addPath(bodyPath)
    ctx.setFillColor(CGColor(red: 0.15, green: 0.4, blue: 0.95, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Gradient fill.
    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let colors = [
        CGColor(red: 0.35, green: 0.72, blue: 1.00, alpha: 1),
        CGColor(red: 0.15, green: 0.47, blue: 1.00, alpha: 1),
        CGColor(red: 0.08, green: 0.28, blue: 0.88, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: rgb, colors: colors, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: body.minX, y: body.maxY),
                           end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // Soft top sheen.
    let sheen = CGGradient(colorsSpace: rgb, colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen,
                           start: CGPoint(x: body.midX, y: body.maxY),
                           end: CGPoint(x: body.midX, y: body.midY), options: [])
    ctx.restoreGState()

    // Four-point sparkle path with concave sides.
    func star(center c: CGPoint, r: CGFloat, pinch: CGFloat = 0.10) -> CGPath {
        let k = r * pinch
        let p = CGMutablePath()
        p.move(to: CGPoint(x: c.x, y: c.y + r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x - k, y: c.y + k))
        p.closeSubpath()
        return p
    }

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.008), blur: s * 0.02,
                  color: CGColor(red: 0.02, green: 0.1, blue: 0.4, alpha: 0.35))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(star(center: CGPoint(x: s * 0.455, y: s * 0.46), r: s * 0.275))
    ctx.fillPath()
    ctx.addPath(star(center: CGPoint(x: s * 0.715, y: s * 0.715), r: s * 0.105))
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.addPath(star(center: CGPoint(x: s * 0.70, y: s * 0.30), r: s * 0.055))
    ctx.fillPath()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let iconset = (outDir as NSString).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(atPath: iconset)
try FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    let path = (iconset as NSString).appendingPathComponent("\(variant.name).png")
    try render(size: variant.px).write(to: URL(fileURLWithPath: path))
}
print("wrote \(iconset)")
