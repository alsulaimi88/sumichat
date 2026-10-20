import AppKit

/// The window for one account: its own web view, title and unread count.
@MainActor
final class AccountWindow {
    let window: NSWindow
    let browser: BrowserController
    private(set) var unread = 0
    var onUnreadChange: (() -> Void)?

    private let updateButton = PillButton()
    private let translateButton = PillPopUpButton(frame: .zero, pullsDown: true)
    private let layoutButton = PillButton()
    private var theme = Theme.current
    private let titlebarButtons = NSStackView()
    private let titlebarAccessory = NSTitlebarAccessoryViewController()

    var account: Account { didSet { updateTitle() } }
    /// Show the account name in the title once there's more than one account.
    var showsAccountName = false { didSet { updateTitle() } }

    init(account: Account, notifier: Notifier, translator: Translator, cascadeIndex: Int) {
        self.account = account
        browser = BrowserController(account: account, notifier: notifier, translator: translator)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: 720, height: 500)
        window.isReleasedWhenClosed = false // closing just hides it; the Dock icon brings it back
        window.tabbingIdentifier = "SumiChat" // all accounts can share one window as tabs
        window.contentView = browser.webView

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
        applyTheme(theme)

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
        window.titlebarAppearsTransparent = !theme.isOriginal
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
