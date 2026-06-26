import AppKit

// Renders a 1024×1024 app-icon PNG: a rounded-square warm gradient with a white
// SF Symbols thermometer centered on it. Output path is argv[1].
// Used by scripts/make-icon.sh to build AppIcon.icns. Standalone + dependency-free.

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let px = 1024

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { fatalError("could not allocate bitmap") }

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = NSRect(x: 0, y: 0, width: px, height: px)

// Rounded-square background (transparent corners), warm orange→red gradient.
let bg = canvas.insetBy(dx: 64, dy: 64)
let squircle = NSBezierPath(roundedRect: bg, xRadius: 200, yRadius: 200)
squircle.addClip()
let gradient = NSGradient(colors: [
    NSColor(srgbRed: 1.00, green: 0.58, blue: 0.00, alpha: 1),  // orange (top)
    NSColor(srgbRed: 0.86, green: 0.16, blue: 0.13, alpha: 1),  // red (bottom)
])!
gradient.draw(in: bg, angle: -90)

// White thermometer glyph, centered.
let cfg = NSImage.SymbolConfiguration(pointSize: 560, weight: .regular)
if let base = NSImage(systemSymbolName: "thermometer.medium", accessibilityDescription: nil),
   let sym = base.withSymbolConfiguration(cfg) {
    let s = sym.size
    let tinted = NSImage(size: s)
    tinted.lockFocus()
    sym.draw(in: NSRect(origin: .zero, size: s))
    NSColor.white.set()
    NSRect(origin: .zero, size: s).fill(using: .sourceAtop)
    tinted.unlockFocus()
    tinted.draw(in: NSRect(x: (CGFloat(px) - s.width) / 2,
                           y: (CGFloat(px) - s.height) / 2,
                           width: s.width, height: s.height))
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
