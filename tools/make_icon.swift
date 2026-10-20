// Draws the 1024x1024 app icon in one of several styles.
// Usage: swift tools/make_icon.swift <style> <output.png>
//        swift tools/make_icon.swift preview <output.png> [style,style,…]   (side by side)
import AppKit

let styles = ["bloom", "garden", "lilypad", "duet", "badge", "twilight",
              "classic", "lotus", "lotuschat", "midnight", "document"]
let args = Array(CommandLine.arguments.dropFirst())
let style = args.first ?? "classic"
let output = args.count > 1 ? args[1] : "icon_1024.png"
let previewStyles = args.count > 2 ? args[2].split(separator: ",").map(String.init) : styles

let plumTop = hex(0x9B4A9C), plumBottom = hex(0x4A1D5E)
let greenTop = hex(0x4CD97B), greenBottom = hex(0x15994A)
let green = hex(0x22B95C)

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

// MARK: Shared pieces

/// Background tile on Apple's icon grid (824pt square inside the 1024 canvas).
func drawTile(top: NSColor, bottom: NSColor, angle: CGFloat = -90, via: [NSColor] = []) {
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
    NSGradient(colors: [top] + via + [bottom])!.draw(in: tile, angle: angle)
}

/// Rounded chat bubble with a tail at the bottom left (or right).
func drawBubble(_ color: NSColor, rect: NSRect = NSRect(x: 240, y: 320, width: 544, height: 450),
                radius: CGFloat? = nil, tailRight: Bool = false) {
    let r = radius ?? min(160, rect.height * 0.36)
    let k = rect.height / 450
    func x(_ dx: CGFloat) -> CGFloat { tailRight ? rect.maxX - dx * k : rect.minX + dx * k }
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: x(50), y: rect.minY + 60 * k))
    tail.line(to: NSPoint(x: x(-5), y: rect.minY - 75 * k))
    tail.line(to: NSPoint(x: x(180), y: rect.minY + 15 * k))
    tail.close()
    tail.fill()
}

/// "Typing" dots.
func drawDots(center: NSPoint, radius: CGFloat, spacing: CGFloat, color: NSColor) {
    color.setFill()
    for i in -1...1 {
        let c = NSPoint(x: center.x + CGFloat(i) * spacing, y: center.y)
        NSBezierPath(ovalIn: NSRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)).fill()
    }
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
func drawLotusFlower(x: CGFloat, y: CGFloat, scale: CGFloat,
                     outer: NSColor = hex(0xE7A9CF), middle: NSColor = hex(0xF5CFE5), center: NSColor = .white,
                     line: NSColor? = hex(0xFFFFFF, 0.85)) {
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

    for side: CGFloat in [-1, 1] { petal(angle: 66 * side, length: 270, width: 120, color: outer) }
    for side: CGFloat in [-1, 1] { petal(angle: 34 * side, length: 360, width: 140, color: middle) }
    petal(angle: 0, length: 430, width: 160, color: center)

    // Water line under the flower.
    guard let line else { return }
    line.setFill()
    let bar = NSRect(x: x - 212 * scale, y: y - 60 * scale, width: 424 * scale, height: 30 * scale)
    NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2).fill()
}

/// Plum lotus on a white bubble, for green backgrounds.
func drawPlumLotus(x: CGFloat, y: CGFloat, scale: CGFloat) {
    drawLotusFlower(x: x, y: y, scale: scale, outer: hex(0xC77DB6), middle: hex(0xA4529A), center: hex(0x6B2D74),
                    line: hex(0x6B2D74, 0.45))
}

/// Plum tile, green chat bubble, white lotus inside.
func drawBloom() {
    drawTile(top: plumTop, bottom: plumBottom)
    drawBubble(green)
    drawLotusFlower(x: 512, y: 440, scale: 0.55)
}

/// Green tile, white chat bubble, plum lotus inside.
func drawGarden() {
    drawTile(top: greenTop, bottom: greenBottom)
    drawBubble(.white)
    drawPlumLotus(x: 512, y: 440, scale: 0.55)
}

/// Plum tile; the lotus grows out of a green chat bubble that's "typing".
func drawLilypad() {
    drawTile(top: plumTop, bottom: plumBottom)
    drawLotusFlower(x: 512, y: 455, scale: 0.8, line: nil)
    drawBubble(green, rect: NSRect(x: 210, y: 250, width: 604, height: 230), radius: 100)
    drawDots(center: NSPoint(x: 512, y: 365), radius: 24, spacing: 76, color: .white)
}

/// Two chat bubbles in conversation: green behind, plum in front holding the lotus.
func drawDuet() {
    drawTile(top: hex(0xFFFFFF), bottom: hex(0xEFE6F1))
    drawBubble(green, rect: NSRect(x: 380, y: 450, width: 430, height: 330), radius: 130, tailRight: true)
    drawBubble(.white, rect: NSRect(x: 200, y: 262, width: 500, height: 396), radius: 156)
    drawBubble(hex(0x7E3584), rect: NSRect(x: 216, y: 278, width: 468, height: 364), radius: 140)
    drawLotusFlower(x: 450, y: 385, scale: 0.45)
}

/// Plum tile with the lotus, and a green message badge in the corner.
func drawBadge() {
    drawTile(top: plumTop, bottom: plumBottom)
    drawLotusFlower(x: 470, y: 320, scale: 0.85)
    let badge = NSRect(x: 590, y: 640, width: 260, height: 200)
    drawBubble(hex(0x8C4392), rect: badge.insetBy(dx: -18, dy: -18), radius: 98)
    drawBubble(green, rect: badge, radius: 80)
    drawDots(center: NSPoint(x: badge.midX, y: badge.midY), radius: 17, spacing: 54, color: .white)
}

/// Plum fading into green, white chat bubble, plum lotus inside.
func drawTwilight() {
    drawTile(top: hex(0x9B3F9A), bottom: hex(0x1FB65A), angle: -50, via: [hex(0x5B58B8), hex(0x1E9BB0)])
    drawBubble(.white)
    drawPlumLotus(x: 512, y: 440, scale: 0.55)
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
    case "bloom": drawBloom()
    case "garden": drawGarden()
    case "lilypad": drawLilypad()
    case "duet": drawDuet()
    case "badge": drawBadge()
    case "twilight": drawTwilight()
    case "lotus": drawLotus()
    case "lotuschat": drawLotusChat()
    case "midnight": drawMidnight()
    case "document": drawDocument()
    default: drawClassic()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Grid of icons, three per row, each with a small Dock-size copy to check it still reads.
func renderPreview() -> NSBitmapImageRep {
    let cell: CGFloat = 440, gap: CGFloat = 40, rowHeight: CGFloat = 600, columns = min(3, previewStyles.count)
    let rows = (previewStyles.count + columns - 1) / columns
    let width = CGFloat(columns) * (cell + gap) + gap
    let height = CGFloat(rows) * rowHeight
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let icons = previewStyles.map(render) // render before taking over the context
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    hex(0xF2F2F4).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    for (i, icon) in icons.enumerated() {
        let x = gap + CGFloat(i % columns) * (cell + gap)
        let y = height - CGFloat(i / columns + 1) * rowHeight
        icon.draw(in: NSRect(x: x, y: y + 130, width: cell, height: cell), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: false, hints: nil)
        icon.draw(in: NSRect(x: x + 10, y: y + 30, width: 72, height: 72), from: .zero, operation: .sourceOver,
                  fraction: 1, respectFlipped: false, hints: nil)
        drawText("\(i + 1). \(previewStyles[i].capitalized)", size: 40, weight: .semibold, color: hex(0x222222),
                 centeredIn: NSRect(x: x + 90, y: y + 30, width: cell - 100, height: 72))
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let rep = style == "preview" ? renderPreview() : render(style)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
