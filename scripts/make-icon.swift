// Draws the Kairos app icon and writes Resources/AppIcon.icns.
// Run: swift scripts/make-icon.swift
import AppKit

func render(to url: URL) {
    let side = 1024
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: an 824pt tile centered on a 1024pt canvas.
    let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28,
                  color: NSColor.black.withAlphaComponent(0.28).cgColor)
    NSColor.black.setFill()
    tilePath.fill()
    ctx.restoreGState()

    // Background: dusk indigo to violet.
    NSGradient(colors: [
        NSColor(srgbRed: 0.36, green: 0.45, blue: 1.00, alpha: 1),
        NSColor(srgbRed: 0.55, green: 0.31, blue: 0.92, alpha: 1),
    ])!.draw(in: tilePath, angle: -90)

    // Glass sheen across the top.
    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    // Rim light.
    NSColor.white.withAlphaComponent(0.35).setStroke()
    let rim = NSBezierPath(roundedRect: tile.insetBy(dx: 3, dy: 3), xRadius: 183, yRadius: 183)
    rim.lineWidth = 6
    rim.stroke()

    // Two stacked cards: clipboard history.
    func card(center: NSPoint, angle: CGFloat, fill: NSColor, shadow: Bool) -> NSBezierPath {
        let rect = NSRect(x: -205, y: -250, width: 410, height: 500)
        let path = NSBezierPath(roundedRect: rect, xRadius: 64, yRadius: 64)
        var t = AffineTransform()
        t.translate(x: center.x, y: center.y)
        t.rotate(byDegrees: angle)
        path.transform(using: t)
        ctx.saveGState()
        if shadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34,
                          color: NSColor(srgbRed: 0.15, green: 0.08, blue: 0.4, alpha: 0.45).cgColor)
        }
        fill.setFill()
        path.fill()
        ctx.restoreGState()
        return path
    }

    let back = card(center: NSPoint(x: 470, y: 548), angle: 10,
                    fill: NSColor.white.withAlphaComponent(0.34), shadow: false)
    NSColor.white.withAlphaComponent(0.55).setStroke()
    back.lineWidth = 4
    back.stroke()

    _ = card(center: NSPoint(x: 540, y: 486), angle: -4,
             fill: NSColor.white.withAlphaComponent(0.96), shadow: true)

    // Text lines on the front card.
    ctx.saveGState()
    ctx.translateBy(x: 540, y: 486)
    ctx.rotate(by: -4 * .pi / 180)
    let ink = NSColor(srgbRed: 0.42, green: 0.40, blue: 0.95, alpha: 1)
    for (i, width) in [280.0, 280, 190].enumerated() {
        let y = 120 - Double(i) * 78
        let bar = NSBezierPath(roundedRect: NSRect(x: -140, y: y, width: width, height: 34), xRadius: 17, yRadius: 17)
        ink.withAlphaComponent(i == 0 ? 0.85 : 0.35).setFill()
        bar.fill()
    }
    // A small "moment" dot.
    let dot = NSBezierPath(ovalIn: NSRect(x: 76, y: -170, width: 64, height: 64))
    NSColor(srgbRed: 0.98, green: 0.62, blue: 0.30, alpha: 1).setFill()
    dot.fill()
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let master = root.appendingPathComponent("Resources/AppIcon.png")
render(to: master)

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func run(_ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    p.waitUntilExit()
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = size * scale
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        run(["sips", "-z", "\(px)", "\(px)", master.path, "--out", iconset.appendingPathComponent(name).path])
    }
}
run(["iconutil", "-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path])
print("Wrote Resources/AppIcon.icns")
