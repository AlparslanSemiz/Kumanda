// Draws Kumanda's app icon: a game controller on a deep blue squircle.
import AppKit
let out = CommandLine.arguments[1]
let size: CGFloat = 1024
let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
    let body = r.insetBy(dx: 100, dy: 100)
    let path = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGradient(colors: [NSColor(srgbRed: 0.27, green: 0.45, blue: 0.98, alpha: 1),
                        NSColor(srgbRed: 0.13, green: 0.20, blue: 0.62, alpha: 1)])!.draw(in: path, angle: -90)
    let cfg = NSImage.SymbolConfiguration(pointSize: 470, weight: .medium).applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
        let s = sym.size
        sym.draw(in: NSRect(x: r.midX - s.width / 2, y: r.midY - s.height / 2, width: s.width, height: s.height))
    }
    return true
}
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
