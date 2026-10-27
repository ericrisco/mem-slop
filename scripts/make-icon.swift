// Draws the MemSlop app icon (a memory chip dripping slop) and writes a 1024 px PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-1024.png"

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
    // Squircle body on Apple's 824 px grid.
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSGradient(colors: [color(0x2A2470), color(0x110E2E)])!.draw(in: squircle, angle: -90)
    NSGraphicsContext.current?.restoreGraphicsState()

    NSGraphicsContext.current?.saveGraphicsState()
    squircle.addClip()
    // Soft glow behind the chip.
    NSGradient(colors: [color(0x6B7BFF, 0.35), color(0x6B7BFF, 0)])!
        .draw(in: NSBezierPath(ovalIn: NSRect(x: 212, y: 330, width: 600, height: 600)), relativeCenterPosition: .zero)

    // Chip pins.
    let chip = NSRect(x: 292, y: 470, width: 440, height: 300)
    color(0xC9CDF5).setFill()
    for index in 0..<7 {
        let x = chip.minX + 42 + CGFloat(index) * 60
        NSBezierPath(roundedRect: NSRect(x: x, y: chip.maxY - 6, width: 24, height: 60), xRadius: 8, yRadius: 8).fill()
        NSBezierPath(roundedRect: NSRect(x: x, y: chip.minY - 54, width: 24, height: 60), xRadius: 8, yRadius: 8).fill()
    }

    // Slop melting off the bottom of the chip: a band plus three drips, filled as one shape.
    let slop = NSBezierPath()
    slop.windingRule = .nonZero
    slop.appendRoundedRect(NSRect(x: chip.minX, y: chip.minY - 46, width: chip.width, height: 120), xRadius: 48, yRadius: 48)
    let drips: [(x: CGFloat, width: CGFloat, length: CGFloat)] = [(376, 62, 150), (486, 84, 250), (626, 66, 190)]
    for drip in drips {
        slop.appendRoundedRect(NSRect(x: drip.x - drip.width / 2, y: chip.minY - drip.length, width: drip.width, height: drip.length),
                               xRadius: drip.width / 2, yRadius: drip.width / 2)
    }
    NSGradient(colors: [color(0xFFB347), color(0xFA5A3C)])!.draw(in: slop, angle: -90)

    // Chip body.
    let chipPath = NSBezierPath(roundedRect: chip, xRadius: 48, yRadius: 48)
    NSGradient(colors: [color(0x5BF0C0), color(0x22C79A)])!.draw(in: chipPath, angle: -90)
    // Die.
    let die = NSBezierPath(roundedRect: chip.insetBy(dx: 120, dy: 80), xRadius: 26, yRadius: 26)
    color(0x0E3B33, 0.35).setFill()
    die.fill()
    // Gloss on the longest drip.
    color(0xFFFFFF, 0.35).setFill()
    NSBezierPath(roundedRect: NSRect(x: 466, y: chip.minY - 200, width: 14, height: 60), xRadius: 7, yRadius: 7).fill()
    NSGraphicsContext.current?.restoreGraphicsState()
    return true
}

guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
