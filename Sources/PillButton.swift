import AppKit

/// Rounded "pill" buttons for the title bar: a soft tint, or a gradient (Restart to Update).
@MainActor
protocol Pill: NSButton {
    var fill: NSColor { get set }
    var gradient: [NSColor]? { get set }
    var textColor: NSColor { get set }
    var isHovered: Bool { get set }
}

extension Pill {
    func drawPill() {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        if let gradient, let shading = NSGradient(colors: gradient) {
            shading.draw(in: path, angle: 0)
        } else {
            fill.setFill()
            path.fill()
        }
        if isHovered {
            NSColor.white.withAlphaComponent(0.18).setFill()
            path.fill()
        }
    }

    func setText(_ text: String) {
        let font = NSFont.systemFont(ofSize: 12, weight: gradient == nil ? .medium : .semibold)
        attributedTitle = NSAttributedString(string: text, attributes: [.foregroundColor: textColor, .font: font])
        contentTintColor = textColor
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    func trackHover() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }
}

final class PillButton: NSButton, Pill {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var gradient: [NSColor]? { didSet { needsDisplay = true } }
    var textColor: NSColor = .labelColor { didSet { setText(title) } }
    var isHovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        imagePosition = .imageLeading
        imageHugsTitle = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 22, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawPill()
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackHover()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}

final class PillPopUpButton: NSPopUpButton, Pill {
    var fill: NSColor = .clear { didSet { needsDisplay = true } }
    var gradient: [NSColor]? { didSet { needsDisplay = true } }
    var textColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    var isHovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect, pullsDown: Bool) {
        super.init(frame: frame, pullsDown: pullsDown)
        isBordered = false
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        let size = super.intrinsicContentSize
        return NSSize(width: size.width + 14, height: 24)
    }

    override func draw(_ dirtyRect: NSRect) {
        drawPill()
        super.draw(dirtyRect)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackHover()
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
}
