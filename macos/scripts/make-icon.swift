// Draws the app icon (a big red arcade button in a dark enclosure) and writes AppIcon.icns.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.icns
import AppKit

let output = CommandLine.arguments.dropFirst().first ?? "Resources/AppIcon.icns"

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let full = NSRect(x: 0, y: 0, width: s, height: s)

    // Enclosure: rounded square, dark charcoal with a subtle vertical gradient.
    let body = NSBezierPath(roundedRect: full.insetBy(dx: s * 0.1, dy: s * 0.1), xRadius: s * 0.19, yRadius: s * 0.19)
    NSGradient(starting: NSColor(white: 0.24, alpha: 1), ending: NSColor(white: 0.1, alpha: 1))!.draw(in: body, angle: -90)

    // Bezel ring.
    let bezel = NSBezierPath(ovalIn: full.insetBy(dx: s * 0.2, dy: s * 0.2))
    NSGradient(starting: NSColor(white: 0.55, alpha: 1), ending: NSColor(white: 0.18, alpha: 1))!.draw(in: bezel, angle: -90)

    // Red dome.
    let dome = NSBezierPath(ovalIn: full.insetBy(dx: s * 0.255, dy: s * 0.255))
    NSGradient(colors: [NSColor(red: 1, green: 0.36, blue: 0.3, alpha: 1), NSColor(red: 0.86, green: 0.06, blue: 0.05, alpha: 1),
                        NSColor(red: 0.55, green: 0.02, blue: 0.02, alpha: 1)])!
        .draw(in: dome, relativeCenterPosition: NSPoint(x: -0.25, y: 0.35))

    // Highlight.
    let shine = NSBezierPath(ovalIn: NSRect(x: s * 0.36, y: s * 0.56, width: s * 0.22, height: s * 0.12))
    NSColor(white: 1, alpha: 0.35).setFill()
    shine.fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon-\(getpid()).iconset")
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output]
try! task.run()
task.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("wrote \(output)")
