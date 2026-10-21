import AppKit

/// A look for SumiChat: colours for the window frame and its buttons, plus CSS that repaints
/// WhatsApp Web through its own colour settings (the `--WDS-…` variables it styles itself with).
/// If WhatsApp renames those, the page simply keeps its own colours.
struct Theme {
    let id: String
    let name: String
    /// Light or dark: also sets the page's light/dark mode (for WhatsApp's "System default").
    let isDark: Bool
    /// Title bar and window background.
    let chrome: NSColor
    let accent: NSColor
    /// Second colour of the "Restart to Update" gradient.
    let accent2: NSColor
    let pillFill: NSColor
    let pillText: NSColor
    /// WhatsApp colour settings to override; empty means WhatsApp's own look.
    let palette: [String: String]

    var isOriginal: Bool { palette.isEmpty }

    /// One of the palette's colours, if this theme sets it.
    func color(_ name: String) -> NSColor? {
        palette[name].flatMap { NSColor(css: $0) }
    }

    // MARK: The themes

    static let sumi = Theme(
        id: "sumi", name: "Sumi Lotus", isDark: false,
        chrome: hex(0xF6ECF3), accent: hex(0x1FAF55), accent2: hex(0xC76FA6),
        pillFill: hex(0x9B4A9C, 0.10), pillText: hex(0x6B2D74),
        palette: [
            "accent": "#1FAF55", "accent-emphasized": "#168C43", "accent-deemphasized": "#DDF4E6",
            "content-on-accent": "#FFFFFF", "persistent-always-branded": "#1FAF55",
            "content-action-emphasized": "#1FAF55", "content-action-default": "#7A5E78",
            "content-default": "#2B1E2E", "content-deemphasized": "#7C6A7A",
            "surface-default": "#FFFFFF", "surface-emphasized": "#FBF5F9", "surface-highlight": "#F6EBF3",
            "surface-pressed": "#EFE0EA", "surface-elevated-default": "#FFFFFF", "surface-elevated-emphasized": "#FBF5F9",
            "background-wash-plain": "#F6ECF3", "background-wash-inset": "#F2E6EF",
            "components-surface-nav-bar": "#F6ECF3", "components-active-list-row": "#F3E4EE",
            "components-filter-surface-selected": "#DDF4E6",
            "lines-divider": "#EEE1EA", "lines-outline-default": "#E4D3DF", "lines-outline-deemphasized": "#F0E5ED",
            // Close to WhatsApp's own beige (#EFEAE2), with only a hint of lotus.
            "systems-chat-background-wallpaper": "#F1EBE6", "systems-chat-foreground-wallpaper": "rgba(110, 90, 100, 0.06)",
            "systems-bubble-surface-incoming": "#FFFFFF", "systems-bubble-surface-outgoing": "#D9F6E3",
            "systems-chat-surface-composer": "#FFFFFF", "systems-chat-surface-tray": "#FBF5F9",
        ]
    )

    static let midnight = Theme(
        id: "midnight", name: "Midnight", isDark: true,
        chrome: hex(0x0E1720), accent: hex(0x2FD27A), accent2: hex(0x3BA3FF),
        pillFill: hex(0x2FD27A, 0.14), pillText: hex(0x7BE8AE),
        palette: [
            "accent": "#2FD27A", "accent-emphasized": "#5BE39A", "accent-deemphasized": "#12392A",
            "content-on-accent": "#04230F", "persistent-always-branded": "#2FD27A",
            "content-action-emphasized": "#2FD27A", "content-action-default": "#8DA1B2",
            "content-default": "#E6EEF4", "content-deemphasized": "#8DA1B2",
            "surface-default": "#111A22", "surface-emphasized": "#16212B", "surface-highlight": "#1D2B37",
            "surface-pressed": "#22323F", "surface-elevated-default": "#18242F", "surface-elevated-emphasized": "#1D2B37",
            "background-wash-plain": "#0C141B", "background-wash-inset": "#0F1820",
            "components-surface-nav-bar": "#0E1720", "components-active-list-row": "#1C2A36",
            "components-filter-surface-selected": "#12392A",
            "lines-divider": "#1F2C38", "lines-outline-default": "#2A3a48", "lines-outline-deemphasized": "#1A2630",
            "systems-chat-background-wallpaper": "#0D151C", "systems-chat-foreground-wallpaper": "rgba(47, 210, 122, 0.05)",
            "systems-bubble-surface-incoming": "#1A2631", "systems-bubble-surface-outgoing": "#11523A",
            "systems-chat-surface-composer": "#18242F", "systems-chat-surface-tray": "#131D26",
        ]
    )

    static let lagoon = Theme(
        id: "lagoon", name: "Lagoon", isDark: false,
        chrome: hex(0xE7F4F8), accent: hex(0x1595B3), accent2: hex(0x2FC3A0),
        pillFill: hex(0x1595B3, 0.10), pillText: hex(0x0F6C83),
        palette: [
            "accent": "#1595B3", "accent-emphasized": "#0F7790", "accent-deemphasized": "#DDF1F7",
            "content-on-accent": "#FFFFFF", "persistent-always-branded": "#1595B3",
            "content-action-emphasized": "#1595B3", "content-action-default": "#557985",
            "content-default": "#12313B", "content-deemphasized": "#5F7F8A",
            "surface-default": "#FFFFFF", "surface-emphasized": "#F4FAFC", "surface-highlight": "#E8F5F9",
            "surface-pressed": "#DCEFF5", "surface-elevated-default": "#FFFFFF", "surface-elevated-emphasized": "#F4FAFC",
            "background-wash-plain": "#E7F4F8", "background-wash-inset": "#E1F0F5",
            "components-surface-nav-bar": "#E7F4F8", "components-active-list-row": "#E1F1F6",
            "components-filter-surface-selected": "#DDF1F7",
            "lines-divider": "#DCEBF0", "lines-outline-default": "#CFE2E9", "lines-outline-deemphasized": "#E5F1F5",
            // A very faint grey-blue: light, but grey enough that white bubbles still stand out.
            "systems-chat-background-wallpaper": "#ECF2F4", "systems-chat-foreground-wallpaper": "rgba(15, 108, 131, 0.05)",
            "systems-bubble-surface-incoming": "#FFFFFF", "systems-bubble-surface-outgoing": "#C6EAF3",
            "systems-chat-surface-composer": "#FFFFFF", "systems-chat-surface-tray": "#F4FAFC",
        ]
    )

    static let original = Theme(
        id: "original", name: "WhatsApp Original", isDark: false,
        chrome: .windowBackgroundColor, accent: hex(0x1FAF55), accent2: hex(0xC76FA6),
        pillFill: NSColor.labelColor.withAlphaComponent(0.06), pillText: .labelColor,
        palette: [:]
    )

    static let all = [sumi, midnight, lagoon, original]

    private static let key = "Theme"

    /// The theme the user picked (saved), or WhatsApp's own look until they pick one.
    static var current: Theme {
        get { all.first { $0.id == UserDefaults.standard.string(forKey: key) } ?? original }
        set { UserDefaults.standard.set(newValue.id, forKey: key) }
    }

    // MARK: CSS for WhatsApp Web

    /// The page's CSS. WhatsApp sets its colours on inner elements, so ours go on every
    /// element (and win with !important); everything else on the page is left alone.
    var css: String {
        guard !isOriginal else { return "" }
        let variables = palette.sorted { $0.key < $1.key }.map { name, value in
            "--WDS-\(name): \(value) !important;"
        }
        let legacy = [
            "--outgoing-background: \(palette["systems-bubble-surface-outgoing"] ?? "inherit") !important;",
            "--incoming-background: \(palette["systems-bubble-surface-incoming"] ?? "inherit") !important;",
            "--panel-background: \(palette["surface-default"] ?? "inherit") !important;",
        ]
        let accent = palette["accent"] ?? "#1FAF55"
        return """
        *, *::before, *::after { \((variables + legacy).joined(separator: " ")) }
        ::selection { background: color-mix(in srgb, \(accent) 28%, transparent); }
        ::-webkit-scrollbar-thumb { background: color-mix(in srgb, \(accent) 35%, transparent) !important; border-radius: 8px; }
        #sumi-translate-button { color: \(accent) !important; }
        .sumi-translation { border-top-color: color-mix(in srgb, \(accent) 35%, transparent) !important; }
        """
    }
}

private func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}
