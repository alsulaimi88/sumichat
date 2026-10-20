// Draws the 1024x1024 app icon in one of several styles.
// Usage: swift tools/make_icon.swift <style> <output.png>
//        swift tools/make_icon.swift preview <output.png>   (all styles side by side)
// Styles: classic, lotus, lotuschat, midnight, document
import AppKit

let styles = ["classic", "lotus", "lotuschat", "midnight", "document"]
let args = Array(CommandLine.arguments.dropFirst())
let style = args.first ?? "classic"
let output = args.count > 1 ? args[1] : "icon_1024.png"

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

// MARK: Shared pieces

/// Background tile on Apple's icon grid (824pt square inside the 1024 canvas).
func drawTile(top: NSColor, bottom: NSColor) {
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    bottom.setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: top, ending: bottom)!.draw(in: tile, angle: -90)
}

/// Chat bubble with a tail at the bottom left.
func drawBubble(_ color: NSColor, rect: NSRect = NSRect(x: 240, y: 320, width: 544, height: 450)) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 160, yRadius: 160).fill()
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: rect.minX + 50, y: rect.minY + 60))
    tail.line(to: NSPoint(x: rect.minX - 5, y: rect.minY - 75))
    tail.line(to: NSPoint(x: rect.minX + 180, y: rect.minY + 15))
    tail.close()
    tail.fill()
}

func drawDownloadArrow(_ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: 484, y: 515, width: 56, height: 180), xRadius: 14, yRadius: 14).fill()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 412, y: 535))
    head.line(to: NSPoint(x: 612, y: 535))
    head.line(to: NSPoint(x: 512, y: 425))
    head.close()
    head.fill()
    NSBezierPath(roundedRect: NSRect(x: 397, y: 375, width: 230, height: 34), xRadius: 17, yRadius: 17).fill()
}

func drawText(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centeredIn rect: NSRect) {
    var font = NSFont.systemFont(ofSize: size, weight: weight)
    if let rounded = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: rounded, size: size) ?? font }
    let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    let bounds = string.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
    string.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
}

// MARK: Styles

/// Green tile, white bubble, download arrow.
func drawClassic() {
    drawTile(top: hex(0x33D680), bottom: hex(0x0A8C66))
    drawBubble(.white)
    drawDownloadArrow(hex(0x129E6E))
}

/// Five-petal lotus standing on (x, y); scale 1 is about 430pt tall.
func drawLotusFlower(x: CGFloat, y: CGFloat, scale: CGFloat) {
    func petal(angle: CGFloat, length: CGFloat, width: CGFloat, color: NSColor) {
        let length = length * scale, width = width * scale
        let path = NSBezierPath()
        path.move(to: .zero)
        path.curve(to: NSPoint(x: 0, y: length),
                   controlPoint1: NSPoint(x: width, y: length * 0.35),
                   controlPoint2: NSPoint(x: width * 0.55, y: length * 0.85))
        path.curve(to: .zero,
                   controlPoint1: NSPoint(x: -width * 0.55, y: length * 0.85),
                   controlPoint2: NSPoint(x: -width, y: length * 0.35))
        var transform = AffineTransform(translationByX: x, byY: y)
        transform.rotate(byDegrees: angle)
        path.transform(using: transform)
        color.setFill()
        path.fill()
    }

    for side: CGFloat in [-1, 1] { petal(angle: 66 * side, length: 270, width: 120, color: hex(0xE7A9CF)) }
    for side: CGFloat in [-1, 1] { petal(angle: 34 * side, length: 360, width: 140, color: hex(0xF5CFE5)) }
    petal(angle: 0, length: 430, width: 160, color: .white)

    // Water line under the flower.
    hex(0xFFFFFF, 0.85).setFill()
    let line = NSRect(x: x - 212 * scale, y: y - 60 * scale, width: 424 * scale, height: 30 * scale)
    NSBezierPath(roundedRect: line, xRadius: line.height / 2, yRadius: line.height / 2).fill()
}

/// Plum tile with a lotus, matching the Sumi brand.
func drawLotus() {
    drawTile(top: hex(0x9B4A9C), bottom: hex(0x4A1D5E))
    drawLotusFlower(x: 512, y: 360, scale: 1)
}

/// Green tile with a WhatsApp-style round bubble outline, and the Sumi lotus inside it.
func drawLotusChat() {
    drawTile(top: hex(0x5CE68A), bottom: hex(0x17A64A))

    // Ring with a tail at the bottom left: arc all the way round except the tail gap.
    let center = NSPoint(x: 512, y: 532), radius: CGFloat = 272
    let bubble = NSBezierPath()
    bubble.appendArc(withCenter: center, radius: radius, startAngle: 245, endAngle: 213, clockwise: false)
    bubble.line(to: NSPoint(x: 236, y: 244))
    bubble.close()
    bubble.lineWidth = 50
    bubble.lineJoinStyle = .round
    NSColor.white.setStroke()
    bubble.stroke()

    drawLotusFlower(x: 512, y: 430, scale: 0.56)
}

/// Dark tile, green bubble with an "S".
func drawMidnight() {
    drawTile(top: hex(0x2C3A42), bottom: hex(0x0F1518))
    let bubble = NSRect(x: 240, y: 320, width: 544, height: 450)
    drawBubble(hex(0x2BD07A), rect: bubble)
    drawText("S", size: 380, weight: .heavy, color: .white, centeredIn: bubble)
}

/// Blue tile, white bubble holding a PDF page.
func drawDocument() {
    drawTile(top: hex(0x4A90F0), bottom: hex(0x1A4FB0))
    drawBubble(.white)

    // Page with a folded corner.
    let page = NSBezierPath()
    page.move(to: NSPoint(x: 420, y: 385))
    page.line(to: NSPoint(x: 420, y: 700))
    page.line(to: NSPoint(x: 570, y: 700))
    page.line(to: NSPoint(x: 630, y: 640))
    page.line(to: NSPoint(x: 630, y: 385))
    page.close()
    hex(0xE6ECF5).setFill()
    page.fill()
    let fold = NSBezierPath()
    fold.move(to: NSPoint(x: 570, y: 700))
    fold.line(to: NSPoint(x: 570, y: 640))
    fold.line(to: NSPoint(x: 630, y: 640))
    fold.close()
    hex(0xC3CEDD).setFill()
    fold.fill()

    hex(0xB4C0D0).setFill()
    for (y, width) in [(600, 150), (560, 170), (520, 130)] as [(CGFloat, CGFloat)] {
        NSBezierPath(roundedRect: NSRect(x: 445, y: y, width: width, height: 18), xRadius: 9, yRadius: 9).fill()
    }

    let tag = NSRect(x: 385, y: 410, width: 180, height: 70)
    hex(0xE5383B).setFill()
    NSBezierPath(roundedRect: tag, xRadius: 14, yRadius: 14).fill()
    drawText("PDF", size: 46, weight: .heavy, color: .white, centeredIn: tag)
}

// MARK: Rendering

func render(_ style: String) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    switch style {
    case "lotus": drawLotus()
    case "lotuschat": drawLotusChat()
    case "midnight": drawMidnight()
    case "document": drawDocument()
    default: drawClassic()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func renderPreview() -> NSBitmapImageRep {
    let cell: CGFloat = 520, gap: CGFloat = 40
    let width = Int(CGFloat(styles.count) * (cell + gap) + gap)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 660,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let icons = styles.map(render) // render before taking over the context
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    hex(0xF2F2F4).setFill()
    NSRect(x: 0, y: 0, width: CGFloat(width), height: 660).fill()
    for (i, icon) in icons.enumerated() {
        let x = gap + CGFloat(i) * (cell + gap)
        icon.draw(in: NSRect(x: x, y: 120, width: cell, height: cell), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: false, hints: nil)
        drawText("\(i + 1). \(styles[i].capitalized)", size: 44, weight: .semibold, color: hex(0x222222),
                 centeredIn: NSRect(x: x, y: 30, width: cell, height: 70))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep = style == "preview" ? renderPreview() : render(style)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
