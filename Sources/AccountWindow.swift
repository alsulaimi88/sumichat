import AppKit
import WebKit

/// The window for one account: its own web view, title and unread count.
@MainActor
final class AccountWindow {
    let window: NSWindow
    let browser: BrowserController
    private(set) var unread = 0
    var onUnreadChange: (() -> Void)?
    /// This account's WhatsApp profile photo address (from its Profile tab), or empty.
    private(set) var profilePhoto = ""
    var onProfilePhotoChange: (() -> Void)?
    /// An account row in the sidebar was clicked.
    var onSelectAccount: ((UUID) -> Void)?
    private var foundTabs = false

    private let updateButton = PillButton()
    private let translateButton = PillPopUpButton(frame: .zero, pullsDown: true)
    private let layoutButton = PillButton()
    private var theme = Theme.current
    private let titlebarButtons = NSStackView()
    private let titlebarAccessory = NSTitlebarAccessoryViewController()
    private let content: AccountContentView
    private var macLayout = MacLayout.isOn

    var account: Account { didSet { updateTitle() } }
    /// Show the account name in the title once there's more than one account.
    var showsAccountName = false { didSet { updateTitle() } }

    init(account: Account, notifier: Notifier, translator: Translator, cascadeIndex: Int) {
        self.account = account
        browser = BrowserController(account: account, notifier: notifier, translator: translator)
        content = AccountContentView(webView: browser.webView)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false // closing just hides it; the Dock icon brings it back
        window.tabbingIdentifier = "SumiChat" // all accounts can share one window as tabs
        window.contentView = content

        // Pill buttons at the right of the title bar: "Restart to Update" (when an update is
        // ready), Translate, and Separate / Merge (when there's more than one account).
        updateButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        updateButton.isHidden = true
        layoutButton.isHidden = true
        translateButton.isHidden = true
        for button in [updateButton, translateButton, layoutButton] as [NSButton] {
            titlebarButtons.addArrangedSubview(button)
        }
        titlebarButtons.orientation = .horizontal
        titlebarButtons.spacing = 8
        titlebarButtons.alignment = .centerY
        titlebarButtons.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        titlebarAccessory.view = titlebarButtons
        titlebarAccessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(titlebarAccessory)
        content.sidebar.onSelect = { [weak self] item in self?.browser.selectNavItem(item) }
        content.sidebar.onSelectAccount = { [weak self] id in self?.onSelectAccount?(id) }
        browser.onNavChange = { [weak self] items, edge in
            guard let self else { return }
            content.sidebar.update(items)
            foundTabs = items.count >= 2
            updateSidebarVisibility()
            content.band.set(left: edge.left ?? theme.chrome, right: edge.right, split: edge.split)
            content.sidebar.backdrop = edge.left ?? theme.chrome
            let photo = items.first { !$0.avatar.isEmpty }?.avatar ?? ""
            if photo != profilePhoto {
                profilePhoto = photo
                onProfilePhotoChange?()
            }
        }
        applyTheme(theme)
        setMacLayout(macLayout)

        let frameName = account.isPrimary ? "MainWindow" : "Account-\(account.id.uuidString)"
        if !window.setFrameUsingName(frameName) {
            window.center()
            let offset = CGFloat(cascadeIndex) * 32
            window.setFrameOrigin(NSPoint(x: window.frame.minX + offset, y: window.frame.minY - offset))
        }
        window.setFrameAutosaveName(frameName)

        browser.onUnreadCountChange = { [weak self] count in
            guard let self else { return }
            unread = count
            updateTitle()
            onUnreadChange?()
        }
        updateTitle()
        browser.load()
    }

    /// Shows "Separate" while accounts are tabs, "Merge" while they're separate windows.
    func configureLayoutButton(merged: Bool, visible: Bool, target: AnyObject, action: Selector) {
        layoutButton.setText(merged ? "Separate" : "Merge")
        layoutButton.image = NSImage(systemSymbolName: merged ? "rectangle.split.2x1" : "rectangle.stack",
                                     accessibilityDescription: nil)
        layoutButton.toolTip = merged ? "Show each account in its own window" : "Put all accounts in one window as tabs"
        layoutButton.target = target
        layoutButton.action = action
        layoutButton.isHidden = !visible
        refreshTitlebarButtons()
    }

    /// Shows "Restart to Update" once a new version has downloaded (nil hides it).
    func configureUpdateButton(readyVersion: String?, target: AnyObject, action: Selector) {
        updateButton.setText("Restart to Update")
        updateButton.toolTip = readyVersion.map { "SumiChat \($0) is ready. Click to install it and reopen." }
        updateButton.target = target
        updateButton.action = action
        updateButton.isHidden = readyVersion == nil
        refreshTitlebarButtons()
    }

    /// The Translate pull-down: `menu` holds its items (the first item is the button's face).
    func configureTranslateButton(menu: NSMenu?) {
        translateButton.isHidden = menu == nil
        if let menu {
            menu.insertItem(NSMenuItem(title: "Translate", action: nil, keyEquivalent: ""), at: 0)
            translateButton.menu = menu
        }
        styleTranslateFace()
        refreshTitlebarButtons()
    }

    /// The window frame in the theme's colours: a seamless title bar and pill buttons.
    func applyTheme(_ theme: Theme) {
        self.theme = theme
        browser.applyTheme(theme)
        content.sidebar.apply(theme)
        window.titlebarAppearsTransparent = macLayout || !theme.isOriginal
        window.backgroundColor = theme.chrome
        window.appearance = theme.isOriginal ? nil : NSAppearance(named: theme.isDark ? .darkAqua : .aqua)

        updateButton.gradient = [theme.accent, theme.accent2]
        updateButton.textColor = .white
        for pill in [layoutButton, translateButton] as [any Pill] {
            pill.fill = theme.pillFill
            pill.textColor = theme.pillText
        }
        layoutButton.setText(layoutButton.title)
        styleTranslateFace()
        refreshTitlebarButtons()
    }

    /// The account rows at the top of the sidebar (empty with one account).
    func showAccounts(_ accounts: [SidebarAccount]) {
        content.sidebar.update(accounts: accounts)
        updateSidebarVisibility()
    }

    /// The sidebar shows once WhatsApp's tabs are found, or whenever there are accounts to
    /// switch between (a new account's QR code page has no tabs).
    private func updateSidebarVisibility() {
        content.showsSidebar = foundTabs || !content.sidebar.accounts.isEmpty
    }

    /// Mac Layout: the page fills the window under a see-through title bar, with the native
    /// sidebar on the left (once WhatsApp's tabs are found). Off: WhatsApp Web as it comes.
    func setMacLayout(_ on: Bool) {
        macLayout = on
        if on {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = on || !theme.isOriginal
        window.titleVisibility = on ? .hidden : .visible
        window.minSize = NSSize(width: on ? 900 : 720, height: 500)
        content.macLayout = on
        browser.setMacLayout(on)
    }

    private func styleTranslateFace() {
        guard let face = translateButton.menu?.items.first else { return }
        face.attributedTitle = NSAttributedString(string: "Translate", attributes: [
            .foregroundColor: theme.pillText, .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ])
        let symbol = NSImage(systemSymbolName: "translate", accessibilityDescription: "Translate")
        face.image = symbol?.withSymbolConfiguration(.init(paletteColors: [theme.pillText]))
        translateButton.synchronizeTitleAndSelectedItem()
        translateButton.invalidateIntrinsicContentSize()
    }

    private func refreshTitlebarButtons() {
        titlebarAccessory.isHidden = updateButton.isHidden && layoutButton.isHidden && translateButton.isHidden
        titlebarButtons.layoutSubtreeIfNeeded()
        titlebarButtons.setFrameSize(NSSize(width: titlebarButtons.fittingSize.width, height: 28))
    }

    /// Closes the window for good (when the account is removed).
    func tearDown() {
        browser.tearDown()
        window.contentView = nil
        window.close()
    }

    private func updateTitle() {
        var title = AppDelegate.appName
        if showsAccountName { title += " — \(account.name)" }
        if unread > 0 { title += " (\(unread))" }
        window.title = title
    }
}

/// A window's content: the native sidebar (Mac Layout), a strip under the see-through title
/// bar in the page's colour, and the page.
@MainActor
final class AccountContentView: NSView {
    let sidebar = SidebarView()
    let webView: WKWebView
    let band = TitleBand()

    var macLayout = false { didSet { needsLayout = true } }
    /// Whether WhatsApp's tabs were found; without them the page keeps its own strip.
    var showsSidebar = false { didSet { if showsSidebar != oldValue { needsLayout = true } } }

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: NSRect(x: 0, y: 0, width: 1200, height: 800))
        for view in [sidebar, band, webView] as [NSView] { addSubview(view) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let titlebar = macLayout ? titlebarHeight : 0
        let sidebarWidth = macLayout && showsSidebar ? SidebarView.width : 0
        sidebar.isHidden = sidebarWidth == 0
        sidebar.frame = NSRect(x: 0, y: 0, width: sidebarWidth, height: bounds.height)
        sidebar.topInset = titlebar + 16
        band.isHidden = titlebar == 0
        band.frame = NSRect(x: sidebarWidth, y: bounds.height - titlebar, width: bounds.width - sidebarWidth, height: titlebar)
        webView.frame = NSRect(x: sidebarWidth, y: 0, width: bounds.width - sidebarWidth, height: bounds.height - titlebar)
    }

    /// The title bar's height, or 0 when the page isn't under it (full screen, Mac Layout off).
    private var titlebarHeight: CGFloat {
        guard let window else { return 0 }
        return max(0, bounds.height - window.contentLayoutRect.height)
    }
}

/// The strip above the page, under the see-through title bar, in the page's own colours so
/// the page looks like it reaches the top of the window.
@MainActor
final class TitleBand: NSView {
    private var left: NSColor = .windowBackgroundColor
    private var right: NSColor?
    private var split: CGFloat = 0

    func set(left: NSColor, right: NSColor?, split: CGFloat) {
        guard left != self.left || right != self.right || split != self.split else { return }
        self.left = left
        self.right = right
        self.split = split
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        left.setFill()
        bounds.fill()
        guard let right, split > 0, split < bounds.width else { return }
        right.setFill()
        NSRect(x: split, y: 0, width: bounds.width - split, height: bounds.height).fill()
        NSColor.separatorColor.setFill() // continues the page's line between the columns
        NSRect(x: split, y: 0, width: 1, height: bounds.height).fill()
    }
}
