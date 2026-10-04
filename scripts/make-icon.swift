// Draws the app icon (yellow tile, dark "Y") and writes an .iconset folder.
// Usage: swift scripts/make-icon.swift <output.iconset>
import AppKit

let out = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024

    // macOS icon grid: 824 pt tile on a 1024 pt canvas.
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let path = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.set()
    NSColor(calibratedRed: 1.0, green: 0.8, blue: 0.0, alpha: 1).setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 1.0, green: 0.87, blue: 0.22, alpha: 1),
               ending: NSColor(calibratedRed: 0.98, green: 0.71, blue: 0.0, alpha: 1))!
        .draw(in: path, angle: -90)

    var font = NSFont.systemFont(ofSize: 620 * s, weight: .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: 620 * s) { font = f }
    let text = NSAttributedString(string: "Y", attributes: [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.11, alpha: 1),
    ])
    // Centre the glyph on its cap height, not on the line box.
    let baseline = (CGFloat(px) - font.capHeight) / 2
    text.draw(at: NSPoint(x: (CGFloat(px) - text.size().width) / 2, y: baseline + font.descender))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
