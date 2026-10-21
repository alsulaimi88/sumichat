import AppKit

/// One of WhatsApp Web's navigation buttons (Chats, Status, Communities, Settings, …),
/// as the page reports it.
struct NavItem: Decodable, Equatable {
    let index: Int
    let label: String
    let icon: String
    let selected: Bool
    let badge: String
    let avatar: String
    let bottom: Bool

    /// A Mac symbol for the tab, from WhatsApp's icon name or label.
    var symbolName: String {
        let key = (icon + " " + label).lowercased()
        let table: [(String, String)] = [
            ("archiv", "archivebox"), ("star", "star"), ("chat", "message"), ("call", "phone"),
            ("status", "circle.dashed"), ("update", "circle.dashed"), ("newsletter", "megaphone"),
            ("channel", "megaphone"), ("communit", "person.3"), ("meta", "sparkles"), ("media", "photo.on.rectangle"),
            ("setting", "gearshape"), ("profile", "person.crop.circle"), ("lock", "lock"),
            ("tool", "wrench.and.screwdriver"), ("advert", "chart.line.uptrend.xyaxis"), ("business", "briefcase"),
        ]
        return table.first { key.contains($0.0) }?.1 ?? "circle"
    }
}

/// A linked account, for the account rows at the top of the sidebar.
struct SidebarAccount: Equatable {
    let id: UUID
    let name: String
    let unread: Int
    /// WhatsApp profile photo address, or empty.
    let photo: String
    let isCurrent: Bool
}

/// The native sidebar: the accounts (when there's more than one), then WhatsApp's tabs as
/// Mac rows, main tabs at the top and Settings / Profile at the bottom.
@MainActor
final class SidebarView: NSView {
    static let width: CGFloat = 224

    var onSelect: ((NavItem) -> Void)?
    var onSelectAccount: ((UUID) -> Void)?
    /// Space left free at the top for the window's buttons.
    var topInset: CGFloat = 52 { didSet { if topInset != oldValue { needsLayout = true } } }
    private(set) var items: [NavItem] = []
    private(set) var accounts: [SidebarAccount] = []

    /// The floating panel the rows sit on: Liquid Glass on macOS 26, a translucent
    /// sidebar with a soft shadow before that.
    private let panel: NSView
    private let rows = FlippedView()
    private let panelShadow = NSView()
    private let accountStack = NSStackView()
    private let topStack = NSStackView()
    private let bottomStack = NSStackView()
    private var style = Style(theme: .original)

    struct Style {
        let tint: NSColor?  // nil: the Mac's own sidebar look
        let text: NSColor
        let secondary: NSColor
        let selection: NSColor
        let hover: NSColor

        init(theme: Theme) {
            tint = theme.isOriginal ? nil : theme.chrome
            text = theme.color("content-default") ?? .labelColor
            secondary = theme.color("content-deemphasized") ?? .secondaryLabelColor
            selection = theme.isOriginal ? NSColor.labelColor.withAlphaComponent(0.09) : theme.pillFill
            hover = theme.isOriginal ? NSColor.labelColor.withAlphaComponent(0.05) : theme.pillFill.withAlphaComponent(0.05)
        }
    }

    static let panelInset: CGFloat = 8
    static let panelRadius: CGFloat = 16

    override init(frame: NSRect) {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.panelRadius
            glass.style = .regular
            glass.contentView = rows
            panel = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .sidebar
            material.blendingMode = .behindWindow
            material.state = .followsWindowActiveState
            material.wantsLayer = true
            material.layer?.cornerRadius = Self.panelRadius
            material.layer?.masksToBounds = true
            material.addSubview(rows)
            panel = material
        }
        super.init(frame: frame)
        wantsLayer = true
        // A soft shadow under the panel, from its own empty layer so the panel can clip its corners.
        panelShadow.wantsLayer = true
        panelShadow.layer?.shadowColor = NSColor.black.cgColor
        panelShadow.layer?.shadowOpacity = 0.10
        panelShadow.layer?.shadowRadius = 12
        panelShadow.layer?.shadowOffset = CGSize(width: 0, height: -3)
        addSubview(panelShadow)
        addSubview(panel)
        for stack in [accountStack, topStack, bottomStack] {
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 2
            rows.addSubview(stack)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        panel.frame = bounds.insetBy(dx: Self.panelInset, dy: Self.panelInset)
        panelShadow.frame = panel.frame
        panelShadow.layer?.shadowPath = CGPath(roundedRect: panelShadow.bounds, cornerWidth: Self.panelRadius,
                                               cornerHeight: Self.panelRadius, transform: nil)
        rows.frame = panel.bounds
        // Rows keep their place in the sidebar's own coordinates, whatever the panel's inset.
        let inset: CGFloat = 8
        let width = rows.bounds.width - inset * 2
        var y = topInset - Self.panelInset
        accountStack.isHidden = accounts.isEmpty
        if !accounts.isEmpty {
            let height = accountStack.fittingSize.height
            accountStack.frame = NSRect(x: inset, y: y, width: width, height: height)
            y += height + 8
        }
        topStack.frame = NSRect(x: inset, y: y, width: width, height: topStack.fittingSize.height)
        let bottomHeight = bottomStack.fittingSize.height
        bottomStack.frame = NSRect(x: inset, y: rows.bounds.height - bottomHeight - 6, width: width, height: bottomHeight)
    }

    /// The colour around the floating panel (the page's own, so the window reads as one piece).
    var backdrop: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        backdrop.setFill()
        bounds.fill()
    }

    func apply(_ theme: Theme) {
        style = Style(theme: theme)
        if #available(macOS 26.0, *), let glass = panel as? NSGlassEffectView {
            glass.tintColor = style.tint?.withAlphaComponent(0.55)
        } else {
            panel.layer?.backgroundColor = style.tint?.cgColor
            (panel as? NSVisualEffectView)?.material = style.tint == nil ? .sidebar : .contentBackground
        }
        rebuildItems()
        rebuildAccounts()
    }

    func update(_ newItems: [NavItem]) {
        guard newItems != items else { return }
        items = newItems
        rebuildItems()
    }

    /// The account rows; empty hides them (one account).
    func update(accounts newAccounts: [SidebarAccount]) {
        guard newAccounts != accounts else { return }
        accounts = newAccounts
        rebuildAccounts()
    }

    private func rebuildItems() {
        for stack in [topStack, bottomStack] {
            stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        }
        for item in items {
            let row = SidebarRow(content: .init(title: item.label, symbol: item.symbolName, photo: item.avatar,
                                                badge: item.badge, selected: item.selected), style: style)
            row.onClick = { [weak self] in self?.onSelect?(item) }
            add(row, to: item.bottom ? bottomStack : topStack)
        }
        needsLayout = true
    }

    private func rebuildAccounts() {
        accountStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        guard !accounts.isEmpty else { needsLayout = true; return }

        let header = NSTextField(labelWithString: "Accounts")
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = style.secondary
        let headerRow = NSView()
        headerRow.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        headerRow.addSubview(header)
        NSLayoutConstraint.activate([
            headerRow.heightAnchor.constraint(equalToConstant: 22),
            header.leadingAnchor.constraint(equalTo: headerRow.leadingAnchor, constant: 8),
            header.centerYAnchor.constraint(equalTo: headerRow.centerYAnchor),
        ])
        add(headerRow, to: accountStack)

        for account in accounts {
            let row = SidebarRow(content: .init(title: account.name, symbol: nil, photo: account.photo,
                                                badge: account.unread > 0 ? String(account.unread) : "",
                                                selected: account.isCurrent,
                                                monogram: (String(account.name.prefix(1)).uppercased(),
                                                           Self.monogramColor(account.id))), style: style)
            row.onClick = { [weak self] in self?.onSelectAccount?(account.id) }
            add(row, to: accountStack)
        }

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        add(line, to: accountStack)
        accountStack.setCustomSpacing(8, after: accountStack.arrangedSubviews[accountStack.arrangedSubviews.count - 2])
        needsLayout = true
    }

    private func add(_ view: NSView, to stack: NSStackView) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    /// A steady colour per account (from its ID), for accounts without a photo yet.
    private static func monogramColor(_ id: UUID) -> NSColor {
        let colors: [NSColor] = [.systemGreen, .systemBlue, .systemPurple, .systemOrange, .systemPink, .systemTeal]
        return colors[Int(id.uuid.0) % colors.count]
    }
}

/// A top-left-origin container for the sidebar rows.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// A sidebar row: icon (or photo), title and unread count.
@MainActor
private final class SidebarRow: NSView {
    struct Content {
        let title: String
        /// SF Symbol name; nil uses the monogram.
        let symbol: String?
        /// Photo address that replaces the icon once it loads, or empty.
        let photo: String
        let badge: String
        let selected: Bool
        var monogram: (String, NSColor)? = nil
    }

    var onClick: (() -> Void)?
    private let content: Content
    private let style: SidebarView.Style
    private let icon = NSImageView()
    private var isHovered = false { didSet { needsDisplay = true } }
    private var isPressed = false { didSet { needsDisplay = true } }

    /// Photos, by address, so rows rebuilt every few seconds don't download again.
    private static var photos: [String: NSImage] = [:]

    init(content: Content, style: SidebarView.Style) {
        self.content = content
        self.style = style
        super.init(frame: NSRect(x: 0, y: 0, width: 190, height: 32))

        if let symbol = content.symbol {
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 15, weight: .regular))
            icon.contentTintColor = style.text
        } else if let (letter, color) = content.monogram {
            icon.image = Self.monogram(letter, color: color)
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        if !content.photo.isEmpty { loadPhoto(content.photo) }

        let label = NSTextField(labelWithString: content.title)
        label.font = .systemFont(ofSize: 13, weight: content.selected ? .medium : .regular)
        label.textColor = style.text
        label.lineBreakMode = .byTruncatingTail

        let badge = NSTextField(labelWithString: content.badge)
        badge.font = .systemFont(ofSize: 12, weight: .regular)
        badge.textColor = style.secondary
        badge.alignment = .right

        for view in [icon, label, badge] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        badge.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 22),
            icon.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            badge.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 6),
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(content.badge.isEmpty ? content.title : "\(content.title), \(content.badge)")
        if content.selected { setAccessibilityValue("selected") }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    private static func monogram(_ letter: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 22, height: 22), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
            let text = NSAttributedString(string: letter, attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
            return true
        }
    }

    private func loadPhoto(_ address: String) {
        if let photo = Self.photos[address] { show(photo); return }
        guard let url = URL(string: address) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = NSImage(data: data) else { return }
            Self.photos[address] = image
            self?.show(image)
        }
    }

    private func show(_ photo: NSImage) {
        icon.image = photo
        icon.contentTintColor = nil
        icon.wantsLayer = true
        icon.layer?.cornerRadius = 11
        icon.layer?.masksToBounds = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let fill: NSColor? = content.selected || isPressed ? style.selection : isHovered ? style.hover : nil
        guard let fill else { return }
        fill.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { isPressed = true }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick?() }
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
