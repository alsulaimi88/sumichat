import AppKit

/// The window for one account: its own web view, title and unread count.
@MainActor
final class AccountWindow {
    let window: NSWindow
    let browser: BrowserController
    private(set) var unread = 0
    var onUnreadChange: (() -> Void)?

    private let updateButton = NSButton()
    private let layoutButton = NSButton()
    private let titlebarButtons = NSStackView()
    private let titlebarAccessory = NSTitlebarAccessoryViewController()

    var account: Account { didSet { updateTitle() } }
    /// Show the account name in the title once there's more than one account.
    var showsAccountName = false { didSet { updateTitle() } }

    init(account: Account, notifier: Notifier, cascadeIndex: Int) {
        self.account = account
        browser = BrowserController(account: account, notifier: notifier)
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

        // Buttons at the right of the title bar: "Restart to Update" (when an update is
        // ready) and Separate / Merge (when there's more than one account).
        updateButton.bezelStyle = .push
        updateButton.bezelColor = .systemGreen
        updateButton.contentTintColor = .white
        updateButton.imagePosition = .imageLeading
        updateButton.image = NSImage(systemSymbolName: "arrow.down.circle.fill", accessibilityDescription: nil)
        updateButton.isHidden = true

        layoutButton.bezelStyle = .recessed
        layoutButton.showsBorderOnlyWhileMouseInside = true
        layoutButton.imagePosition = .imageLeading
        layoutButton.isHidden = true

        for button in [updateButton, layoutButton] {
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: button === updateButton ? .semibold : .regular)
            titlebarButtons.addArrangedSubview(button)
        }
        titlebarButtons.orientation = .horizontal
        titlebarButtons.spacing = 8
        titlebarButtons.alignment = .centerY
        titlebarButtons.edgeInsets = NSEdgeInsets(top: 0, left: 8, bottom: 0, right: 10)
        titlebarAccessory.view = titlebarButtons
        titlebarAccessory.layoutAttribute = .trailing
        window.addTitlebarAccessoryViewController(titlebarAccessory)
        refreshTitlebarButtons()

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
        layoutButton.title = merged ? "Separate" : "Merge"
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
        updateButton.title = "Restart to Update"
        updateButton.toolTip = readyVersion.map { "SumiChat \($0) is ready. Click to install it and reopen." }
        updateButton.target = target
        updateButton.action = action
        updateButton.isHidden = readyVersion == nil
        refreshTitlebarButtons()
    }

    private func refreshTitlebarButtons() {
        titlebarAccessory.isHidden = updateButton.isHidden && layoutButton.isHidden
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
